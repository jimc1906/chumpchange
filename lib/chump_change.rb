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
        
        # Rails also silently prevents modification to the :id attribute
        @always_prevent_modification = [ :created_at, :updated_at ]
        @always_allow_modification = [ @control_column ]

        @attribute_names = @model_class.attribute_names.collect{|v| v.to_sym }
        @association_names = @model_class.reflect_on_all_associations.map(&:name)

        @state_hash = {}
        @associations_config = {}
      end

      def control_by
        @control_column.to_sym
      end

      def always_prevent_change(*fields)
        @always_prevent_modification.concat fields.flatten
      end

      def allow_change_for(control_value, options)
        @state_hash[control_value.to_sym] = options[:attributes] || []
        @associations_config[control_value.to_sym] = options[:associations] || []
      end

      def can_modify_fields?(model, allowed_changes)
        changed = model.changed.collect!{|v| v.to_sym}
        prevented_changes = @always_prevent_modification & (changed - @always_allow_modification)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevented_changes}" unless prevented_changes.empty?

        prevented_changes = changed - (allowed_changes + @always_allow_modification)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevented_changes}" unless prevented_changes.empty?

        true
      end

      def can_modify_associations?(model, allowed_changes)
        @association_names
        changed.collect!{|v| v.to_sym}
        prevented_changes = @always_prevent_modification & (changed - @always_allow_modification)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevented_changes}" unless prevented_changes.empty?

        prevented_changes = changed - (allowed_changes + @always_allow_modification)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevented_changes}" unless prevented_changes.empty?

        true
      end

      def attributes_changed_on_model_association(changed, allowed_changes)
      end

      # Return the fields allowed for the parameter value, if configured.  If the parameter value is not a configured value,
      # then return all attributes
      def fields_allowed_for_value(currvalue)
        allowed = @always_allow_modification + (@state_hash[currvalue] || @attribute_names) - @always_prevent_modification
        allowed.uniq
      end

      def confirm_specified_attributes
        raise ChumpChange::ConfigurationError.new "Invalid control_by attribute specified: #{control_by}" unless @attribute_names.include? control_by.to_sym

        invalid = @always_prevent_modification - @attribute_names
        raise ChumpChange::ConfigurationError.new "Invalid attributes specified for the 'always_prevent_change' value: #{invalid}" unless invalid.empty?

        invalid = @always_allow_modification - @attribute_names
        raise ChumpChange::ConfigurationError.new "Invalid attributes specified for the 'always_allow' value: #{invalid}" unless invalid.empty?

        @state_hash.keys.each do |k|
          invalid = @state_hash[k] - @attribute_names
          raise ChumpChange::ConfigurationError.new "Invalid attributes specified in the 'allow_change_for' configuration for value '#{k}': #{invalid}" unless invalid.empty?
        end

        all_defined_associations = []
        @associations_config.keys.each do |k|
          all_defined_associations << @associations_config[k].map(&:keys)
        end
        all_defined_associations.flatten!.uniq!
        invalid = all_defined_associations - @association_names 
        raise ChumpChange::ConfigurationError.new "Invalid association names specified: #{invalid}" unless invalid.empty?

        overlap = @always_allow_modification & @always_prevent_modification
        raise ChumpChange::ConfigurationError.new "Conflict in 'always_alow' and 'always_prevent_change': #{overlap}" unless overlap.empty?
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

    # May be overridden to allow for custom implementation
    def allowable_change_fields
      # Gracefully handle a nil control value
      ctlval = self.send(@@definition.control_by)
      ctlval = (ctlval ? ctlval.to_sym : ctlval)
      
      @@definition.fields_allowed_for_value(ctlval)
    end

    def review_field_changes
      return true if new_record?

      @@definition.can_modify_fields?(self, self.allowable_change_fields)
      @@definition.can_modify_associations?(self, self.allowable_change_fields)
    end
  end
end
