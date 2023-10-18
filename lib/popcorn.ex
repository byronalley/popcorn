defmodule Popcorn do
  @moduledoc """
  Documentation for `Popcorn`: functions that should be in Kernel but aren't.
  """

  @type result_atom :: :ok | :error

  @type ok_tuple :: {:ok, any()}
  @type error_tuple :: {:error, String.t() | atom}
  @type result_tuple :: ok_tuple() | error_tuple()
  @type maybe_any :: any() | nil

  @type result :: result_atom() | result_tuple()

  @doc """
  Wrap the value in an :ok tuple. The main purpose of this function is to use at the end of a pipe:

    iex> %{foo: "bar"}
    iex> |> Map.get(:foo)
    iex> |> ok()
    {:ok, "bar"}
  """
  @spec ok(any()) :: ok_tuple()
  def ok(value), do: {:ok, value}

  @doc """
  Wrap the message in an :error tuple. The main purpose of this function is to use at the end of a pipe:
    iex> %{error: "fail"}
    iex> |> Map.get(:error)
    iex> |> error()
    {:error, "fail"}
  """
  @spec error(any()) :: error_tuple()
  def error(msg), do: {:error, msg}

  @doc """
  Given a result tuple, maybe execute a function:
  - If the param is an `{:ok, value}` tuple, then run the function
  on `value`.
  - If it's an `{:error, msg}` tuple, return that.

  This is mainly an alternative to using `with` blocks, so that
  you can pipe a function that returns a tuple, directly
  into another function that expects a simple value -- but only
  if it's a success tuple:

    iex> {:ok, [1, 2, 3]}
    iex> |> Popcorn.bind(& Enum.fetch(&1, 0))
    {:ok, 1}

    iex> {:error, :invalid}
    iex> |> Popcorn.bind(&to_string/1)
    {:error, :invalid}

    Note that you can't give it an `:ok` atom as input because there's no clearly defined behaviour for this: it's not an error but also shouldn't be expected to be used as input directly into another function.
  """
  @spec bind(result_tuple() | :error, (any() -> result_tuple() | result_atom())) :: result_tuple()
  def bind({:ok, value}, f), do: ensure_is_result(f.(value))
  def bind({:error, _} = error_tuple, _), do: error_tuple
  def bind(:error), do: :error

  @spec ensure_is_result(any) :: result_tuple | result_atom | no_return
  def ensure_is_result(any) do
    case any do
      {:ok, _} -> any
      {:error, _} -> any
      :ok -> any
      :error -> any
    end
  rescue
    CaseClauseError -> raise ArgumentError, "Expected argument to return a result tuple or atom"
  end

  @doc """
  Maybe execute a function if the given param is not nil:
  - If the param is not `nil`, then run the function on `value`.
  - If it's an `{:error, msg}` tuple, return that.

  This is mainly an alternative to using `with` blocks, so that
  you can pipe a function that returns a tuple, directly
  into another function that expects a simple value -- but only
  if it's a success tuple:

    iex> 10
    iex> |> Popcorn.maybe(&to_string/1)
    "10"

    iex> nil
    iex> |> Popcorn.maybe(&to_string/1)
    nil
  """
  @spec maybe(maybe_any(), (any -> any)) :: maybe_any()
  def maybe(nil, _f), do: nil
  def maybe(value, f), do: f.(value)

  @doc """
  Macro to wrap a function call so that it returns a result tuple instead of raising an exception.
    iex> tuple_wrap(5 + 5)
    {:ok, 10}

    iex> tuple_wrap(div(10, 0))
    {:error, "bad argument in arithmetic expression"}

    iex> tuple_wrap(raise FunctionClauseError)
    {:error, "FunctionClauseError"}

  ## Returns
  * `{:ok, result}` on success
  * `{:error, "string message"}` if the exception has a non-nil message
  * `{:error, "ExceptionModule"}` otherwise
  """
  defmacro tuple_wrap(function_call) do
    quote do
      (fn ->
         try do
           {:ok, unquote(function_call)}
         rescue
           error ->
             case error do
               %{message: msg} when not is_nil(msg) -> {:error, msg}
               %{__struct__: type} -> {:error, inspect(type)}
             end
         end
       end).()
    end
  end

  @doc """
  Shorter alias for the identity function (Function.identity/1)

  The downside is that it could conflict with using `id` as a variable name.
  """
  @spec id(term) :: term
  defdelegate id(term), to: Function, as: :identity

  @doc """
  Bind alias

  iex> {:ok, "3.14"} ~> &String.to_float/1
  {:ok, 3.14}

  """
  @spec result_tuple() ~> (any() -> result_tuple()) :: result_tuple()
  defdelegate result_tuple ~> f, to: __MODULE__, as: :bind

  @doc """
    iex> {:ok, "happy"} &&& {:ok, "success"}
    {:ok, "success"}

    iex> {:ok, "happy"} &&& {:error, "failure"}
    {:error, "failure"}

    iex> {:error, "failure"} &&& {:ok, "happy"}
    {:error, "failure"}

  """
  def result1 &&& result2 do
    case {result1, result2} do
      {{:ok, _}, result_tuple} -> result_tuple
      {{:error, _} = err, _} -> err
      _ -> raise ArgumentError
    end
  end

  @doc """
    iex> {:ok, "happy"} ||| {:ok, "success"}
    {:ok, "happy"}

    iex> {:ok, "happy"} ||| {:error, "failure"}
    {:ok, "happy"}

    iex> {:error, "failure"} ||| {:ok, "happy"}
    {:ok, "happy"}

    iex> {:error, "failure"} ||| {:error, "oops"}
    {:error, "oops"}
  """
  def result1 ||| result2 do
    case {result1, result2} do
      {{:ok, _} = success, _} -> success
      {{:error, _}, result} -> result
      _ -> raise ArgumentError
    end
  end
end
