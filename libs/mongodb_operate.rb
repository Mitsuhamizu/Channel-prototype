def insert_with_check(coll, doc)
  view = coll.find({ id: doc[:id] })
  if view.count_documents() != 0
    puts "sry, there is an record already, please using reset msg."
    return false
  else
    coll.insert_one(doc)
    return true
  end
end
