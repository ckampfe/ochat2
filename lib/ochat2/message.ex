defmodule Ochat2.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :body, :string
    field :who, :string

    belongs_to :conversation, Ochat2.Conversation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :who])
    |> validate_required([:body, :who])
    |> validate_length(:body, min: 1)
  end
end
