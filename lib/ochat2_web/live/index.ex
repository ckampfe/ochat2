defmodule Ochat2Web.IndexLive do
  use Ochat2Web, :live_view

  alias Ochat2.Repo
  alias Ochat2.{Conversation, Message}

  import Ecto.Query

  def mount(_params, _session, socket) do
    conversations =
      Conversation
      |> join(
        :inner,
        [c],
        m in subquery(
          Message
          |> select([m], %{
            conversation_id: m.conversation_id,
            last_message_inserted_at: max(m.inserted_at)
          })
          |> group_by([m], m.conversation_id)
        ),
        on: m.conversation_id == c.id
      )
      |> join(:left, [c, lm], c2 in Conversation, on: [id: c.source_conversation_id])
      |> order_by([c, lm, c2], desc: c.inserted_at)
      |> select([c, lm, c2], %{
        id: c.id,
        name: c.name,
        source_conversation_name: c2.name,
        source_conversation_id: c2.id,
        inserted_at: c.inserted_at,
        last_message_inserted_at: lm.last_message_inserted_at
      })
      |> Repo.all()

    socket =
      socket
      |> assign(:conversations, conversations)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container mb-5">
      <div>
        <h2>Conversations</h2>
        <.link navigate={~p"/conversations/new"}>New</.link>
      </div>
      <table class="table container">
        <thead>
          <tr>
            <th>started</th>
            <th>last message</th>
            <th>name</th>
            <th>source</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={conversation <- @conversations}>
            <td>{conversation.inserted_at}</td>
            <td>{conversation.last_message_inserted_at}</td>
            <td>
              <.link class="link" navigate={~p"/conversations/#{conversation.id}"}>
                {conversation.name}
              </.link>
            </td>
            <td :if={conversation.source_conversation_name}>
              <.link class="link" navigate={~p"/conversations/#{conversation.source_conversation_id}"}>
                {conversation.source_conversation_name}
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
