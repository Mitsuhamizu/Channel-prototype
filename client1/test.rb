require "json"
require "ostruct"
person = OpenStruct.new
person = OpenStruct.new
person.name = "John Smith"
person.age = 70

person.name      # => "John Smith"
person.age       # => 70
person.address   # => nil
# str = "{ \"capacity\":200988405368, \"index\": 0, \"tx_hash\": \"0xa5fce2bf780e03f090863d5dda6e13767d5464f190e672e62e362128d180249a\" }"
# cells = { capacity: 200988405368, index: 0, tx_hash: "0xa5fce2bf780e03f090863d5dda6e13767d5464f190e672e62e362128d180249a" }
# cell_array = Array.new()
# cell_array << cells
# cell_array << cells
# cells = cell_array.to_json
# puts cells

# cells = JSON.parse(str)
# puts cells
# a="123"
# c=a.delete!("\n")
# puts c.class
