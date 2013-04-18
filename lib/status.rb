module ChumpChange

  module Status

    def attribute_control_disabled?
      Thread.current[:attribute_control_disabled] == true
    end

    def attribute_control_enabled?
      Thread.current[:attribute_control_disabled] == false
    end

    def disable_attribute_control
      Thread.current[:attribute_control_disabled] = true
    end

    def enable_attribute_control
      Thread.current[:attribute_control_disabled] = false
    end

    def without_attribute_control
      previously_disabled = attribute_control_disabled?

      begin
        disable_attribute_control
        result = yield if block_given?
      ensure
        enable_attribute_control unless previously_disabled
      end

      result
    end

    def with_attribute_control
      previously_disabled = attribute_control_disabled?

      begin
        enable_attribute_control
        result = yield if block_given?
      ensure
        disable_attribute_control if previously_disabled
      end

      result
    end

  end

end
