import prologue

import ./views

const urlPatterns* = @[
  pattern("/", todoList),
  pattern("/new", newItem),
  pattern("/edit/{id}/{task}", editItem),
  pattern("/item/{item}", showItem)
]
