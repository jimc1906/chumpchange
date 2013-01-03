require "attr_control/version"

module AttrControl
  module AttributeGuardian

    class Definition
      def initialize(base, options = {})
	@model_class = base

	puts 'here'
	raise "Missing control column value" if options[:control_by].nil?
	puts 'and hehere'

	@control_column = driver_attr
	@always_prevent_modification = [ :id, :created_at, :updated_at ]
	@always_allow_modification = [ :state ]  # TODO

	@state_hash = {}
      end

      def always_prevent(*fields)
	@always_prevent_modification.concat fields.flatten
      end

      def allow_modification(state, *fields)
	@state_hash[state.to_sym] = fields.flatten
      end

      def can_modify_fields_for_state?(state, changed)
	changed.collect!{|v| v.to_sym}
	prevent = @always_prevent_modification & changed
	raise "Attempt has been made to modify restricted fields: #{prevent}" unless prevent.empty?

	prevent = changed - fields_allowed_for_state(state)
	raise "Attempt has been made to modify restricted fields: #{prevent}" unless prevent.empty?

	true
      end

      def fields_allowed_for_state(currstate)
	@always_allow_modification + @state_hash[currstate.to_sym]
      end

      def confirm_specified_attributes
	class_attributes = @model_class.attribute_names.collect{|v| v.to_sym }

	invalid = @always_prevent_modification - class_attributes
	raise "Invalid attributes specified for the 'always_prevent' value: #{invalid}" unless invalid.empty?

	invalid = @always_allow_modification - class_attributes
	raise "Invalid attributes specified for the 'always_allow' value: #{invalid}" unless invalid.empty?

	@state_hash.keys.each do |k|
	  invalid = @state_hash[k] - class_attributes
	  raise "Invalid attributes specified for the 'allow_modification' value with state '#{k}': #{invalid}" unless invalid.empty?
	end

	overlap = @always_allow_modification & @always_prevent_modification
	raise "Conflict in 'always_alow' and 'always_prevent': #{overlap}" unless overlap.empty?
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
      @@definition.fields_allowed_for_state(self.state.to_sym)
    end

    def review_field_changes
      return true if new_record?
      @@definition.can_modify_fields_for_state?(self.state, self.changed)
    end
  end
end
