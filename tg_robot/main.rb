require "telegram/bot"

token = "896274990:AAEOmszCWLd2dLCL7PGWFlBjJjtxQOHmJpU"
# group id: -1001372639358
# channel id: group_id
# Zhichun: 1115979019
# Zhuoyu: 1256191191
Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    group_id = -1001372639358
    channel_id = group_id
    message_id = 50
    case message.text

    when "/start"
      bot.api.pinChatMessage(chat_id: group_id, message_id: message_id, disable_notification: false)
    when "/stop"
      bot.api.unpinChatMessage(chat_id: group_id, message_id: message_id, disable_notification: false)
    when "/getChat"
      chat = bot.api.getChat(chat_id: group_id)
      puts chat.keys()
      puts chat["result"].class
      puts chat["result"]["pinned_message"] == nil
    when "/send"
      ret = bot.api.send_message(chat_id: group_id, text: "123")
      ret = bot.api.pinChatMessage(chat_id: group_id, message_id: ret["result"]["message_id"], disable_notification: false)
      puts ret
    end
  end
end
