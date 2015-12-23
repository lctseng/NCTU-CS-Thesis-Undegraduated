module TokenAdder

  # ret: true/false
  def control_add_token(n)
    @control_api.add_token(n)
  end
  
  
  # ////////////////
  # Registration
  # ////////////////
  def register_control_api(control)
    @control_api = control
    @control_api.register_token_adder(self)
    post_register
  end

  def post_register

  end

end
