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
    case message.text

    when "/start"
      chatpermission = {
        "can_send_messages": false,
      }
      bot.api.restrictChatMember(chat_id: group_id, user_id: 1256191191, permissions: chatpermission, until_date: 1603266073)
      # bot.api.send_message(chat_id: group_id, text: "Unmute zhuoyu.")
      # bot.api.promoteChatMember(chat_id: group_id, user_id: 1256191191, can,can_edit_messages: true)
      # bot.api.editMessageText(chat_id: group_id, message_id: 22, text: "modified!")
      # bot.api.editMessageText(chat_id: group_id, message_id: 10, can_pin_messages: false)
      # bot.api.send_message(chat_id: group_id, text: "hi, #{message.chat.id}")
      # bot.api.send_message(chat_id: group_id, text: "Now, you can not delete msg: #{1256191191}")
    when "/stop"
      bot.api.promoteChatMember(chat_id: group_id, user_id: 1256191191, can_post_messages: false)
      # bot.api.send_message(chat_id: group_id, text: "Mute zhuoyu.")
    end
  end
end
