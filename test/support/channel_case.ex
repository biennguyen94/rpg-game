defmodule HacLongWeb.ChannelCase do
  @moduledoc "Test cho Channel: có database (sandbox dùng chung) và tiện ích tạo người chơi."
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import HacLongWeb.ChannelCase
      @endpoint HacLongWeb.Endpoint
    end
  end

  setup tags do
    # Tiến trình Session (không phải tiến trình test) cũng ghi database,
    # nên sandbox phải ở chế độ dùng chung: test Channel không chạy async.
    HacLong.DataCase.setup_sandbox(Map.put(tags, :async, false))

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(HacLong.Game.SessionSupervisor),
          do: DynamicSupervisor.terminate_child(HacLong.Game.SessionSupervisor, pid)
    end)

    :ok
  end

  def create_user(name \\ "nguoichoi#{System.unique_integer([:positive])}") do
    {:ok, user} = HacLong.Accounts.register(%{"username" => name, "password" => "matkhau1"})
    user
  end
end
