defmodule Ochat2.Repo do
  use Ecto.Repo,
    otp_app: :ochat2,
    adapter: Ecto.Adapters.SQLite3
end
