defmodule Ochat2Web.PageController do
  use Ochat2Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
