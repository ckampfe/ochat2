defmodule Ochat2.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :name, :string
    field :model_id, :id
    field :source_conversation_id, :id

    has_many :messages, Ochat2.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
