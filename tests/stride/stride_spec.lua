local stride = require("stride")

describe("setup", function()
  it("works with default", function()
    assert(stride.hello() == "Hello!", "my first function with param = Hello!")
  end)

  it("works with custom var", function()
    stride.setup({ opt = "custom" })
    assert(stride.hello() == "custom", "my first function with param = custom")
  end)
end)
