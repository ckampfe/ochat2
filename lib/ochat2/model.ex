defmodule Ochat2.Model do
  use Ecto.Schema
  import Ecto.Changeset

  schema "models" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(model, attrs) do
    model
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
