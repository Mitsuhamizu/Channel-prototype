require "json"
data_json = {}
data_json[:test] = 1
file = File.new("./result.json", "w")
file.syswrite(data_json)

# data_raw = File.read("./result.json")

# data_json = JSON.parse(data_raw, symbolize_names: true, :quirks_mode => true)
# puts data_raw
