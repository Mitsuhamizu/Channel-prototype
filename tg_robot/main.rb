require "telegram/bot"

token = "896274990:AAEOmszCWLd2dLCL7PGWFlBjJjtxQOHmJpU"

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when "/start"
      bot.api.promoteChatMember(chat_id: -1001160566093, user_id: 1256191191, can_edit_messages: true)
      # bot.api.editMessageText(chat_id: -1001160566093, message_id: 22, text: "modified!")
      # bot.api.editMessageText(chat_id: -1001160566093, message_id: 10, can_pin_messages: false)

      # bot.api.send_message(chat_id: -1001160566093, text: "Now, you can not delete msg: #{1256191191}")
    when "/stop"
      bot.api.send_message(chat_id: -1001160566093, text: "Bye, #{message.from.first_name}")
    end
  end
end
