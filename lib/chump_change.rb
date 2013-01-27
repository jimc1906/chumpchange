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
        @associations_config[control_value.to_sym] = options[:associations] || {}
      end

      def can_modify_fields?(model, allowed_changes)
        changed = model.changed.collect!{|v| v.to_sym}
        prevented_changes = @always_prevent_modification & (changed - @always_allow_modification)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevented_changes}" unless prevented_changes.empty?

        prevented_changes = changed - (allowed_changes + @always_allow_modification)
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields: #{prevented_changes}" unless prevented_changes.empty?

        true
      end

      def can_modify_association_attributes?(model)
        # find the dsl-configuration for the current model control value
        config_for_control_value = @associations_config[model.send(control_by).to_sym] || {}

        # iterate over each of the defined association names and check for disallowed changes
        config_for_control_value.each do |key, config|
          assoc_instance = model.send(key)

          if assoc_instance.is_a? Enumerable
            assoc_instance.each do |obj|
              check_for_disallowed_changes(obj, config, key)
            end
          else
            check_for_disallowed_changes(assoc_instance, config, key)
          end
        end

        true
      end

      def check_for_disallowed_changes(obj, config, assoc_name)
        return if obj.new_record?  # additions of new records are handled through the before_add hook

        prevented_changes = obj.changed.collect!{|v| v.to_sym} - (config[:attributes] || [])
        raise ChumpChange::Error.new "Attempt has been made to modify restricted fields on #{assoc_name}: #{prevented_changes}" unless prevented_changes.empty?
      end

      def can_alter_association_collection?(action_sym, model, assoc_instance)
        raise "Unknown action #{action_sym} while evaluating association behavior" unless [:create, :delete].include? action_sym

        assoc_def = find_matching_association_definition(assoc_instance)
        config_for_control_value = @associations_config[model.send(control_by).to_sym] || {}
        config_for_control_value = config_for_control_value[assoc_def.name] || {}

        can_perform_action = config_for_control_value["allow_#{action_sym}".to_sym]
        can_perform_action = true if can_perform_action.nil?
        raise ChumpChange::Error.new "Attempt has been made to #{action_sym} association record on :#{assoc_def.name}" unless can_perform_action

        true
      end

      def find_matching_association_definition(assoc_instance)
        assoc_name = assoc_instance.class.name.underscore # e.g., flip from LineItem to line_item

        # get singular or plural version
        assoc = @model_class.reflect_on_association(assoc_name) || @model_class.reflect_on_association(assoc_name.pluralize)
        return assoc if assoc.present?

        # not found as :line_item or :line_items...look to the :class_name option that may have been used in the association definition
        assoc = @model_class.reflect_on_all_associations.detect{|a| a.class_name == assoc_instance.class.name.split('::').last}

        raise "Association not found on #{@model_class.name} for #{assoc_instance.class.name}" if assoc.nil?
        return assoc
      end

      # Return the fields allowed for the parameter value, if configured.  If the parameter value is not a configured value,
      # then return all attributes
      def fields_allowed_for_value(currvalue)
        allowed = @always_allow_modification + (@state_hash[currvalue] || @attribute_names) - @always_prevent_modification
        allowed.uniq
      end

      def fields_allowed_for_association_for_value(currvalue, assoc_name)
        config_for_control_value = @associations_config[currvalue] || {}
        config_for_control_value[assoc_name.to_sym][:attributes] || []
      end

      def operations_allowed_for_association_for_value(currvalue, assoc_name)
        config_for_control_value = @associations_config[currvalue] || {}
        allowed = []

        [:create, :delete].each do |action|
          can_perform_action = config_for_control_value[assoc_name.to_sym]["allow_#{action}".to_sym]
          can_perform_action = true if can_perform_action.nil?
          allowed << action if can_perform_action
        end

        allowed
      end

      def confirm_specified_attributes
        return if @configuration_confirmed

        raise ChumpChange::ConfigurationError.new "Invalid control_by attribute specified: #{control_by}" unless @attribute_names.include? control_by.to_sym

        invalid = @always_prevent_modification - @attribute_names
        raise ChumpChange::ConfigurationError.new "Invalid attributes specified for the 'always_prevent_change' value: #{invalid}" unless invalid.empty?

        invalid = @always_allow_modification - @attribute_names
        raise ChumpChange::ConfigurationError.new "Invalid attributes specified for the 'always_allow' value: #{invalid}" unless invalid.empty?

        @state_hash.keys.each do |k|
          invalid = @state_hash[k] - @attribute_names
          raise ChumpChange::ConfigurationError.new "Invalid attributes specified in the 'allow_change_for' configuration for value '#{k}': #{invalid}" unless invalid.empty?
        end

        #TODO: check attributes specified on association configs

        all_defined_associations = @associations_config.values.inject([]) {|result,v| result << v.keys}
        all_defined_associations.flatten!.uniq!

        invalid = all_defined_associations - @association_names 
        raise ChumpChange::ConfigurationError.new "Invalid association names specified: #{invalid}" unless invalid.empty?

        overlap = @always_allow_modification & @always_prevent_modification
        raise ChumpChange::ConfigurationError.new "Conflict in 'always_allow' and 'always_prevent_change': #{overlap}" unless overlap.empty?

        @configuration_confirmed = true
      end
    end

    def self.included(base)
      base.class_eval do
        before_save :review_model_value_changes
      end

      base.instance_eval do
        # Override activerecord/lib/active_record/associations.rb implementation of has_many to add the 
        # call to our guard methods for the before_add and before_remove options
        def has_many(name, options={}, &extension)
          options[:before_add] = ([options[:before_add]].flatten + [:guard_before_create]).compact
          options[:before_remove] = ([options[:before_remove]].flatten + [:guard_before_delete]).compact
          super
        end

        def attribute_control(options, &block)
          @@definition = Definition.new(self, options)
          @@definition.instance_eval &block
          
          reflect_on_all_associations.map(&:name).each do |an|
            define_method("allowable_change_fields_for_#{an}") do
              @@definition.fields_allowed_for_association_for_value(current_control_value, an.to_sym)
            end

            define_method("allowable_operations_for_#{an}") do
              @@definition.operations_allowed_for_association_for_value(current_control_value, an.to_sym)
            end
          end
        end
      end
    end

    def current_control_value
      # Gracefully handle a nil control value
      ctlval = self.send(@@definition.control_by)
      (ctlval ? ctlval.to_sym : ctlval)
    end
    
    # May be overridden to allow for custom implementation
    def allowable_change_fields
      @@definition.fields_allowed_for_value(current_control_value)
    end

    class_eval do
      # create the guard_before_create and guard_before_delete methods
      [:create,:delete].each do |i| 
        define_method("guard_before_#{i}") do |assoc|
          return if new_record?
          
          @@definition.confirm_specified_attributes

          @@definition.can_alter_association_collection?(i, self, assoc)
        end
      end
    end

    def review_model_value_changes
      return if new_record?

      @@definition.confirm_specified_attributes

      @@definition.can_modify_fields?(self, self.allowable_change_fields)
      @@definition.can_modify_association_attributes?(self)
    end
  end
end
