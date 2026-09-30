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
    post "/logout", AuthController, :logout
    post "/logout_all", AuthController, :logout_all
    post "/password", AuthController, :password
  end

  scope "/", HacLongWeb do
    get "/", PageController, :index
  end
end
