require "chump_change/version"
require "configuration_error"

module ChumpChange

  class Error < StandardError
  end

  module AttributeGuardian

    class Definition
      def initialize(base, options = {})
        @model_class = base

        raise ChumpChange::ConfigurationError, "Missing control column value" if options[:control_by].nil?

        @control_column = options[:control_by]
        @always_prevent_modification = [ :id, :created_at, :updated_at ]
        @always_allow_modification = [ @control_column ]

        @state_hash = {}
      end

      def control_by
        @control_column.to_sym
      end

      def always_prevent(*fields)
        @always_prevent_modification.concat fields.flatten
      end

      def allow_modification(control_value, *fields)
        @state_hash[control_value.to_sym] = fields.flatten
      end

      def can_modify_fields_for_value?(value, changed)
        changed.collect!{|v| v.to_sym}
        prevent = @always_prevent_modification & changed
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevent}" unless prevent.empty?

        prevent = changed - fields_allowed_for_value(value)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevent}" unless prevent.empty?

        true
      end

      # Return the fields allowed for the parameter value, if configured.  If the parameter value is not a configured value,
      # then return all attributes
      def fields_allowed_for_value(currvalue)
        allowed = @always_allow_modification + (@state_hash[currvalue.to_sym] || all_available_attributes)
        allowed.uniq
      end

      def all_available_attributes
        @model_class.attribute_names.collect{|v| v.to_sym }
      end

      def confirm_specified_attributes
        class_attributes = all_available_attributes
        raise ChumpChange::ConfigurationError.new "Invalid control_by attribute specified: #{control_by}" unless class_attributes.include? control_by.to_sym

        invalid = @always_prevent_modification - class_attributes
        raise ChumpChange::ConfigurationError.new "Invalid attributes specified for the 'always_prevent' value: #{invalid}" unless invalid.empty?

        invalid = @always_allow_modification - class_attributes
        raise ChumpChange::ConfigurationError.new "Invalid attributes specified for the 'always_allow' value: #{invalid}" unless invalid.empty?

        @state_hash.keys.each do |k|
          invalid = @state_hash[k] - class_attributes
          raise ChumpChange::ConfigurationError.new "Invalid attributes specified in the 'allow_modification' configuration for value '#{k}': #{invalid}" unless invalid.empty?
        end

        overlap = @always_allow_modification & @always_prevent_modification
        raise ChumpChange::ConfigurationError.new "Conflict in 'always_alow' and 'always_prevent': #{overlap}" unless overlap.empty?
      end
    end

    def self.included(base)
      base.class_eval do
        before_save :review_field_changes
      end

      base.instance_eval do
        def attribute_control(options, &block)
          @@definition = Definition.new(self, options)
          @@definition.instance_eval &block
          @@definition.confirm_specified_attributes
        end
      end
    end

    def allowable_change_fields
      @@definition.fields_allowed_for_value(self.send(@@definition.control_by).to_sym)
    end

    def review_field_changes
      return true if new_record?
      @@definition.can_modify_fields_for_value?(self.send(@@definition.control_by), self.changed)
    end
  end
end
