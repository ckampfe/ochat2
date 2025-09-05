defmodule Ochat2Web.ConversationLive do
  use Ochat2Web, :live_view

  alias Ochat2.{Conversation, Message, Model}
  alias Ochat2.Repo
  import Ecto.Query
  require Logger

  @filled_block "\u{2588}"
  @empty_block "\u{3000}"

  def get_available_models!() do
    %{body: %{"models" => models}} =
      "http://localhost:11434/api/tags"
      |> Req.get!()

    Enum.map(models, fn model -> model["name"] end)
  end

  def send_chat_message_async(new_message, previous_messages, model, response_pid) do
    Task.start(fn ->
      all_messages = previous_messages ++ [new_message]

      prompt =
        all_messages
        |> Enum.map(fn message ->
          "#{message.who}: #{message.body}"
        end)
        |> Enum.join("\n")

      body = %{"model" => model, "prompt" => prompt}

      case Req.post("http://localhost:11434/api/generate",
             json: body,
             into: fn {:data, data}, {req, resp} ->
               Logger.debug(data)
               Kernel.send(response_pid, {:chat_response_chunk, JSON.decode!(data)})
               {:cont, {req, resp}}
             end,
             connect_options: [
               timeout: :timer.minutes(2)
             ],
             receive_timeout: :timer.minutes(2)
           ) do
        {:ok, _} -> nil
        {:error, e} -> Kernel.send(response_pid, {:chat_response_error, e})
      end
    end)
  end

  def mount(%{"conversation_id" => conversation_id}, _session, socket) do
    conversation =
      Conversation
      |> join(:left, [c], c2 in Conversation, on: c2.source_conversation_id == c.id)
      |> join(:inner, [c, c2], m in Model, on: m.id == c.model_id)
      |> where([c, c2, m], c.id == ^conversation_id)
      |> limit(1)
      |> select(
        [c, c2, m],
        %{
          id: c.id,
          name: c.name,
          model_name: m.name,
          model_id: m.id,
          source_conversation_id: c.source_conversation_id,
          source_conversation_name: c2.name,
          inserted_at: c.inserted_at
        }
      )
      |> Repo.one()

    messages =
      Message
      |> where([m], m.conversation_id == ^conversation.id)
      |> order_by([m], asc: m.inserted_at)
      |> select([m], [:id, :body, :who, :conversation_id, :inserted_at])
      |> Repo.all()

    socket =
      socket
      |> assign_async(:models, fn ->
        available_models = get_available_models!()

        # ok because sqlite
        Repo.transact(fn ->
          Enum.each(available_models, fn model ->
            Repo.insert!(%Model{name: model},
              on_conflict: :nothing
            )
          end)

          {:ok,
           %{
             models:
               Model
               |> order_by([m], m.name)
               |> Repo.all()
           }}
        end)
      end)
      |> assign(:conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:chat_input, to_form(%{"body" => ""}))
      |> assign(:selected_model_name, conversation.model_name)
      |> assign(:response_message_id, nil)
      |> assign(:ticker, nil)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="m-4">
      <section>
        <div class="mb-2">
          <a href="/conversations" class="link">Back</a>
        </div>
        <div>
          <div :if={@models.loading}>Loading models...</div>
          <select :if={models = @models.ok? && @models.result} class="select">
            <%= for model <- models do %>
              <option
                selected={model.name == @selected_model_name}
                phx-click="select-model"
                phx-value-model_id={model.id}
              >
                {model.name}
              </option>
            <% end %>
          </select>
          <div :if={error = @models.failed}>{error}</div>
        </div>
      </section>
      <section>
        <table class="table">
          <thead>
            <tr>
              <th class="hidden sm:table-cell"></th>
              <th class="hidden sm:table-cell"></th>
              <th class="hidden sm:table-cell"></th>
              <th></th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{message, i} <- Enum.with_index(@messages)}>
              <td class="hidden sm:table-cell">{i + 1}</td>
              <td class="hidden sm:table-cell">{message.inserted_at}</td>
              <td class="hidden sm:table-cell">{message.who}</td>
              <td class="">{message.body}</td>
              <td>
                <a
                  phx-click="fork-conversation"
                  phx-value-message_id={message.id}
                  class="link"
                >
                  Fork
                </a>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
      <section class="flex mb-4">
        <.form
          for={@chat_input}
          phx-change="update-input"
          phx-submit="send-chat-message"
          class="w-screen"
        >
          <.input
            class="textarea w-full focus:outline-none"
            type="textarea"
            field={@chat_input[:body]}
            required
          />
          <button class="btn btn-xl sm:btn-md">Send</button>
        </.form>
      </section>
    </div>
    """
  end

  def handle_event(
        "select-model",
        %{"value" => model_name, "model_id" => model_id} = _unsigned_params,
        socket
      ) do
    model_id = String.to_integer(model_id)

    Conversation
    |> where([c], c.id == ^socket.assigns.conversation.id)
    |> update(
      set: [
        model_id: ^model_id
      ]
    )
    |> Repo.update_all([])

    socket =
      socket
      |> assign(:selected_model_name, model_name)

    {:noreply, socket}
  end

  def handle_event("fork-conversation", %{"message_id" => message_id} = _unsigned_params, socket) do
    message_id = String.to_integer(message_id)

    {:ok, new_conversation_id} =
      Repo.transact(fn ->
        new_conversation =
          %Conversation{
            name: "a new conversation",
            source_conversation_id: socket.assigns.conversation.id,
            model_id: socket.assigns.conversation.model_id
          }
          |> Repo.insert!()

        latest_message_from_source_conversation =
          Message
          |> where([m], m.id == ^message_id)
          |> Repo.one!()

        Repo.insert_all(
          Message,
          Message
          |> where([m], m.conversation_id == ^socket.assigns.conversation.id)
          |> where([m], m.inserted_at <= ^latest_message_from_source_conversation.inserted_at)
          |> where([m], m.id <= ^message_id)
          |> select([m], %{
            who: m.who,
            body: m.body,
            conversation_id: ^new_conversation.id
          })
        )

        {:ok, new_conversation.id}
      end)

    {:noreply, push_navigate(socket, to: ~p"/conversations/#{new_conversation_id}")}
  end

  def handle_event("update-input", %{"body" => body} = _unsigned_params, socket) do
    socket =
      socket
      |> assign(:chat_input, to_form(%{"body" => body}))

    {:noreply, socket}
  end

  def handle_event("send-chat-message", %{"body" => body} = _unsigned_params, socket) do
    my_message =
      Repo.insert!(%Message{
        who: "Me",
        body: body,
        conversation_id: socket.assigns.conversation.id
      })

    response_message =
      Repo.insert!(%Message{
        body: "",
        who: "LlaMa",
        conversation_id: socket.assigns.conversation.id
      })

    socket =
      socket
      |> assign(:response_message_id, response_message.id)
      |> Phoenix.Component.update(:messages, fn messages ->
        messages ++ [my_message]
      end)

    send_chat_message_async(
      my_message,
      socket.assigns.messages,
      socket.assigns.selected_model_name,
      self()
    )

    socket =
      socket
      |> Phoenix.Component.update(:messages, fn messages ->
        messages ++ [response_message]
      end)
      |> assign(:chat_input, to_form(%{"body" => ""}))
      |> assign(:ticker, Process.send_after(self(), :tick, :timer.seconds(1)))

    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    socket =
      socket
      |> assign(:ticker, Process.send_after(self(), :tock, :timer.seconds(1)))
      |> Phoenix.Component.update(:messages, fn messages ->
        List.update_at(messages, -1, fn message ->
          %{message | body: @filled_block}
        end)
      end)

    {:noreply, socket}
  end

  def handle_info(:tock, socket) do
    socket =
      socket
      |> assign(:ticker, Process.send_after(self(), :tick, :timer.seconds(1)))
      |> Phoenix.Component.update(:messages, fn messages ->
        List.update_at(messages, -1, fn message ->
          %{message | body: @empty_block}
        end)
      end)

    {:noreply, socket}
  end

  def handle_info({:chat_response_chunk, %{"done" => true}}, socket) do
    socket =
      socket
      |> assign(:response_message_id, nil)
      |> Phoenix.Component.update(:messages, fn messages ->
        List.update_at(messages, -1, fn message ->
          %{message | body: String.replace(message.body, @filled_block, "")}
        end)
      end)

    {:noreply, socket}
  end

  def handle_info({:chat_response_chunk, %{"done" => false, "response" => response}}, socket) do
    Message
    |> where([m], m.id == ^socket.assigns.response_message_id)
    |> Ecto.Query.update(
      set: [
        body: fragment("body || ?", ^response)
      ]
    )
    |> Repo.update_all([])

    socket =
      socket
      |> Phoenix.Component.update(:messages, fn messages ->
        List.update_at(messages, -1, fn message ->
          new_body =
            message.body
            |> String.replace(@filled_block, "")
            |> String.replace(@empty_block, "")
            |> Kernel.<>(response)
            |> Kernel.<>(@filled_block)

          %{message | body: new_body}
        end)
      end)
      |> Phoenix.Component.update(:ticker, fn
        nil ->
          nil

        ticker ->
          Process.cancel_timer(ticker)
          nil
      end)

    {:noreply, socket}
  end

  def handle_info({:chat_response_error, error}, socket) do
    socket =
      socket
      |> Phoenix.Component.update(:ticker, fn
        nil ->
          nil

        ticker ->
          Process.cancel_timer(ticker)
          nil
      end)
      |> Phoenix.Component.update(:messages, fn messages ->
        List.update_at(messages, -1, fn message ->
          %{message | body: inspect(error)}
        end)
      end)

    {:noreply, socket}
  end
end
