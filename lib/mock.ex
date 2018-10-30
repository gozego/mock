defmodule Mock do
  @moduledoc """
  Mock modules for testing purposes. Usually inside a unit test.

  Please see the README file on github for a tutorial

  ## Example

      defmodule MyTest do
        use ExUnit.Case
        import Mock

        test "get" do
          with_mock HTTPotion,
              [get: fn("http://example.com", _headers) ->
                      HTTPotion.Response.new(status_code: 200,
                          body: "hello") end] do
            # Code which calls HTTPotion.get
            # Check that the call was made as we expected
            assert called HTTPotion.get("http://example.com", :_)
          end
        end
      end
  """

  @doc """
  Mock up `mock_module` with functions specified as a keyword
  list of function_name:implementation `mocks` for the duration
  of `test`.

  `opts` List of optional arguments passed to meck. `:passthrough` will
   passthrough arguments to the original module.

  ## Example

      with_mock(HTTPotion, [get: fn("http://example.com") ->
           "<html></html>" end] do
         # Tests that make the expected call
         assert called HTTPotion.get("http://example.com")
      end
  """
  defmacro with_mock(mock_module, opts \\ [], mocks, do: test) do
    quote do
      unquote(__MODULE__).with_mocks(
       [{unquote(mock_module), unquote(opts), unquote(mocks)}], do: unquote(test))
    end
  end

  @doc """
  Mock up multiple modules for the duration of `test`.

  ## Example
  with_mocks([{HTTPotion, opts, [{get: fn("http://example.com") -> "<html></html>" end}]}]) do
    # Tests that make the expected call
    assert called HTTPotion.get("http://example.com")
  end
  """
  defmacro with_mocks(mocks, do: test) do
    quote do
      mock_modules = mock_modules(unquote(mocks))

      try do
        unquote(test)
      after
        for m <- mock_modules, do: :meck.unload(m)
      end
    end
  end

  @doc """
  Shortcut to avoid multiple blocks when a test requires a single
  mock.

  For full description see `with_mock`.

  ## Example

      test_with_mock "test_name", HTTPotion,
        [get: fn(_url) -> "<html></html>" end] do
        HTTPotion.get("http://example.com")
        assert called HTTPotion.get("http://example.com")
      end
  """
  defmacro test_with_mock(test_name, mock_module, opts \\ [], mocks, test_block) do
    quote do
      test unquote(test_name) do
        unquote(__MODULE__).with_mock(
            unquote(mock_module), unquote(opts), unquote(mocks), unquote(test_block))
      end
    end
  end

  @doc """
  Shortcut to avoid multiple blocks when a test requires a single
  mock. Accepts a context argument enabling information to be shared
  between callbacks and the test.

  For full description see `with_mock`.

  ## Example
      setup do
        doc = "<html></html>"
        {:ok, doc: doc}
      end

      test_with_mock "test_with_mock with context", %{doc: doc}, HTTPotion, [],
        [get: fn(_url) -> doc end] do

        HTTPotion.get("http://example.com")
        assert called HTTPotion.get("http://example.com")
      end
  """
  defmacro test_with_mock(test_name, context, mock_module, opts, mocks, test_block) do
    quote do
      test unquote(test_name), unquote(context) do
        unquote(__MODULE__).with_mock(
            unquote(mock_module), unquote(opts), unquote(mocks), unquote(test_block))
      end
    end
  end

  @doc """
  Use inside a `with_mock` block to determine whether
  a mocked function was called as expected.

  ## Example

      assert called HTTPotion.get("http://example.com")
  """
  defmacro called({ {:., _, [ module, f ]} , _, args }) do
    quote do
      :meck.called unquote(module), unquote(f), unquote(args)
    end
  end

  @doc """
  Use inside a `with_mock` block to determine whether
  a mocked function was called as expected and
  given number of times.

  ## Example

      assert called 2, HTTPotion.get("http://example.com")
  """
  defmacro called(count, {{:., _, [module, f]}, _, args}) do
    quote bind_quoted: [module: module, f: f, args: args, count: count] do
      count === :meck.num_calls module, f, args
    end
  end

  defmacro assert_called(count, {{:., _, [module, f]}, _, args}) do
    quote bind_quoted: [count: count, module: module, f: f, args: args] do
      unless count === :meck.num_calls module, f, args do
        raise_called {module, f, args}, count
      end
    end
  end

  @doc """
  Use inside a `with_mock` block to determine whether
  a mocked function was called as expected. If the assertion fails, 
  the calls that were received are displayed in the assertion message

  ## Example
      assert_called HTTPotion.get("http://example.com")
  """
  defmacro assert_called({{:., _, [module, f]}, _, args}) do
    quote do
      unquoted_module = unquote(module)
      value = :meck.called(unquoted_module, unquote(f), unquote(args))

      unless value do
        raise_called unquoted_module
      end
    end
  end

  def raise_called({m, f, a}, count) do
    mock_calls = get_module_mock_history(m)

    matching_calls =
      mock_calls
      |> Enum.filter(fn
        {{_, {^m, ^f, ^a}, _ret}, _i} -> true
        _other -> false
      end)

    mock_calls =
      mock_calls
      |> pretty_print_calls()
      |> Enum.join("\n")

    raise ExUnit.AssertionError,
      message: "Expected #{count} call(s) for #{pretty_print_mfa(m, f, a)}. Got #{Enum.count(matching_calls)} calls\nCalls which were received:\n\n#{mock_calls}"
  end

  def raise_called(module) do
    module
    |> get_module_mock_history()
    |> pretty_print_calls()
    |> case do
      [] ->
        raise ExUnit.AssertionError,
          message: "Did not receive any call for #{module}"
      calls ->
        raise ExUnit.AssertionError,
          message: "Expected call but did not receive it. Calls which were received:\n\n#{Enum.join(calls, "\n")}"
    end
  end

  defp get_module_mock_history(module) do
    module 
    |> :meck.history()
    |> Enum.with_index()
  end

  defp pretty_print_calls(calls) do
    Enum.map(calls, fn {{_, {m, f, a}, ret}, i} ->
      "#{i}. #{pretty_print_mfa(m, f, a)} (returned #{inspect ret})"
    end)
  end

  defp pretty_print_mfa(m, f, a) do
    "#{m}.#{f}(#{a |> Enum.map(&Kernel.inspect/1) |> Enum.join(",")})"
  end

  @doc """
  Mocks up multiple modules prior to the execution of each test in a case and
  execute the callback specified.

  For full description of mocking, see `with_mocks`.

  For a full description of ExUnit setup, see
  https://hexdocs.pm/ex_unit/ExUnit.Callbacks.html

  ## Example
      setup_with_mocks([
        {Map, [], [get: fn(%{}, "http://example.com") -> "<html></html>" end]}
      ]) do
        foo = "bar"
        {:ok, foo: foo}
      end

      test "setup_all_with_mocks base case" do
        assert Map.get(%{}, "http://example.com") == "<html></html>"
      end
  """
  defmacro setup_with_mocks(mocks, do: setup_block) do
    quote do
      setup do
        mock_modules(unquote(mocks))

        # The mocks are linked to the process that setup all the tests and are
        # automatically unloaded when that process shuts down

        unquote(setup_block)
      end
    end
  end

  @doc """
  Mocks up multiple modules prior to the execution of each test in a case and
  execute the callback specified with a context specified

  See `setup_with_mocks` for more details

  ## Example
      setup_with_mocks([
        {Map, [], [get: fn(%{}, "http://example.com") -> "<html></html>" end]}
      ], context) do
        {:ok, test_string: Atom.to_string(context.test)}
      end

      test "setup_all_with_mocks with context", %{test_string: test_string} do
        assert Map.get(%{}, "http://example.com") == "<html></html>"
        assert test_string == "test setup_all_with_mocks with context"
      end
  """
  defmacro setup_with_mocks(mocks, context, do: setup_block) do
    quote do
      setup unquote(context) do
        mock_modules(unquote(mocks))
        unquote(setup_block)
      end
    end
  end

  # Helper macro to mock modules. Intended to be called only within this module
  # but not defined as `defmacrop` due to the scope within which it's used.
  defmacro mock_modules(mocks) do
    quote do
      Enum.reduce(unquote(mocks), [], fn({m, opts, mock_fns}, ms) ->
        unless m in ms do
          # :meck.validate will throw an error if trying to validate
          # a module that was not mocked
          try do
            if :meck.validate(m), do: :meck.unload(m)
          rescue
            e in ErlangError -> :ok
          end

          :meck.new(m, opts)
        end

        unquote(__MODULE__)._install_mock(m, mock_fns)
        # IO.warn "MOCK: being validated -> #{inspect m}\nfunctions mocked ->#{inspect mock_fns}\nMocked so far: #{inspect ms}"
        # assert :meck.validate(m) == true

        [ m | ms] |> Enum.uniq
      end)
    end
  end

  @doc false
  def _install_mock(_, []), do: :ok
  def _install_mock(mock_module, [ {fn_name, value} | tail ]) do
    :meck.expect(mock_module, fn_name, value)
    _install_mock(mock_module, tail)
  end
end
