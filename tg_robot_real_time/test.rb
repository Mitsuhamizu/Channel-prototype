def test()
    while true
        puts "111"
        sleep(1)
    end
end

Thread.new{test}
puts "222"