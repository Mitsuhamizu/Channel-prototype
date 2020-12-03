a = [[95, 2], [86, 3], [93, 2],
     [83, 2], [90, 2], [90, 3],
     [97, 2], [94, 3], [91, 2],
     [92, 3], [87, 3], [86, 0.5],
     [76, 3], [85, 2], [90, 1],
     [95, 2], [88, 1], [89, 1],
     [85, 12], [95, 1], [85, 2],
     [75, 2]]
total_grade = 0
total_credit = 0
for array in a
  grade = array[0]
  credit = array[1]
  total_grade += grade * credit
  total_credit += credit
end
puts total_grade / total_credit
