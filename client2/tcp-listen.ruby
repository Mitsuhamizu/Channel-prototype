require 'socket'      # Sockets are in standard library  
  
hostname = 'localhost'  
port = 1000  
  
s = TCPSocket.open(hostname, port)  

server = TCPServer.open(1000)  # Socket to listen on port 2000  

loop {                         # Servers run forever  
  client = server.accept       # Wait for a client to connect  
  client.puts(Time.now.ctime)  # Send the time to the client  
  client.puts "Closing the connection. Bye!" 
  client.close                 # Disconnect from the client  
}


while line = s.gets   # Read lines from the socket  
  puts line.chop      # And print with platform line terminator  
end

s.close               # Close the socket when done  
