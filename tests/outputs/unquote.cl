require("moonscript")
require("lisp.lib");
p({
  __S("hello"),
  {
    2,
    {
      {
        __S("print"),
        {
          "hello",
          nil
        }
      },
      {
        4,
        nil
      }
    }
  }
})
p({
  __S("hello"),
  {
    2,
    {
      print("hello"),
      {
        4,
        nil
      }
    }
  }
})
p({
  __S("hello"),
  {
    2,
    __splice({
      "hello",
      {
        "world",
        nil
      }
    }, {
      4,
      nil
    })
  }
})