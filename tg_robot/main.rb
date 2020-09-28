require "telegram/bot"

token = "896274990:AAEOmszCWLd2dLCL7PGWFlBjJjtxQOHmJpU"

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when "/start"
      bot.api.send_message(chat_id: -429847794, text: "Hello, #{message.from.first_name}")
    when "/stop"
      bot.api.send_message(chat_id: -429847794, text: "Bye, #{message.from.first_name}")
    end
  end
end
