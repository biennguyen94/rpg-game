defmodule HacLongWeb.Router do
  use HacLongWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", HacLongWeb do
    pipe_through :api
    post "/register", AuthController, :register
    post "/login", AuthController, :login
    get "/me", AuthController, :me
  end

  scope "/", HacLongWeb do
    get "/", PageController, :index
  end
end
