require 'spec_helper'
require 'status'

module ChumpChange
  module AttributeGuardian
    describe 'AttributeGuardian' do
      
      before(:all) do
        ::ActiveRecord::Migration.create_table :widgets do |t|
          t.integer :id
          t.string :name
          t.integer :one
          t.integer :two
          t.integer :three
          t.integer :four
          t.integer :five
          t.string :state
          t.string :other_control
          t.timestamps
        end
        ::ActiveRecord::Migration.create_table :parts do |t|
          t.integer :id
          t.string :name
          t.string :manufacturer_state
          t.integer :quantity
          t.integer :widget_id
          t.integer :widget_type
          t.timestamps
        end
        ::ActiveRecord::Migration.create_table :contacts do |t|
          t.integer :id
          t.string :name
          t.string :mobile_number
          t.integer :widget_id
          t.integer :widget_type
          t.timestamps
        end
      end

      after(:all) do
        ::ActiveRecord::Migration.drop_table :widgets
        ::ActiveRecord::Migration.drop_table :parts
        ::ActiveRecord::Migration.drop_table :contacts
      end

      context 'should confirm valid configuration' do
        it 'should load with configuration' do
          class WidgetSimpleBasedOnState < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            has_one :part
            has_many :things

            attribute_control({:control_by => :state}) do
              always_prevent_change :name
              allow_change_for 'one', {
                :attributes => [ :one ]
              }
              allow_change_for 'two', {
                :attributes => [:two, :three],
                :associations => { :part => {     # allow_* default to true
                                      :allow_create => true,
                                      :allow_delete => false
                                   },
                                   :things => {
                                       :attributes => [ :city, :state ]
                                   }
                                 }
              }
            end
          end

          w = WidgetSimpleBasedOnState.new
          w.state = 'one'
          w.one = 123
          w.save
          w.one = 456
          w.save  # configuration confirmed in before_save trigger
        end
        
        it 'should load with configuration using confirm_every_save_per_instance setting' do
          class WidgetSimpleWithConfirmSetting < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              confirm_every_save_per_instance false
              allow_change_for 'one', {
                :attributes => [ :one ]
              }
            end
          end

          w = WidgetSimpleWithConfirmSetting.new
          w.state = 'one'
          w.one = 123
          w.save

          # Since we've set confirm_every_save_per_instance to false, no exception
          # will get thrown at this point...still considered a new record
          w.two = 456
          w.save  # configuration confirmed in before_save trigger

          # re-find and save -- should throw exception
          w = WidgetSimpleWithConfirmSetting.find w.id
          w.two = 789
          expect {
            w.save  # configuration confirmed in before_save trigger
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*two/) 
        end

        it 'should load with configuration without confirm_every_save_per_instance' do
          class WidgetSimpleWithoutConfirmSetting < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              # no confirm_every_save_per_instance setting -- defaults to true
              allow_change_for 'one', {
                :attributes => [ :one ]
              }
            end
          end

          w = WidgetSimpleWithoutConfirmSetting.new
          w.state = 'one'
          w.one = 123
          w.save

          expect {
            w.two = 456
            w.save  # configuration confirmed in before_save trigger
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*two/) 
        end

        it 'should load with configuration using control_by method' do
          class WidgetSimpleBasedOnStateMethod < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            has_one :part
            has_many :things

            attribute_control({:control_by => :state_value_method}) do
              always_prevent_change :name
              allow_change_for 'one', {
                :attributes => [ :one ]
              }
              allow_change_for 'two', {
                :attributes => [:two, :three],
                :associations => { :part => {     # allow_* default to true
                                      :allow_create => true,
                                      :allow_delete => false
                                   },
                                   :things => {
                                       :attributes => [ :city, :state ]
                                   }
                                 }
              }
            end

            def state_value_method
              state
            end
          end

          w = WidgetSimpleBasedOnStateMethod.new
          w.state = 'one'
          w.one = 123
          w.save
          w.one = 456
          w.save  # configuration confirmed in before_save trigger
        end
         
        it 'should load with configuration that allows for association' do
          class WidgetPartAssociationConfig < ActiveRecord::Base
            self.table_name = 'parts'

            belongs_to :widget
          end

          class Widget < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            has_one :part, :class_name => 'WidgetPartAssociationConfig'

            attribute_control({:control_by => :state}) do
              always_prevent_change :name
              allow_change_for 'one', {
                 :attributes => [:one],
                 :associations => 
                    {
                      :part => {
                        :attributes => [ :name, :quantity ]
                      }
                    }
              }
              allow_change_for 'two', {
                :attributes => [:two, :three]
              }
            end
          end

          w = Widget.new
          w.state = 'one'
          w.one = 123
          w.build_part({:name => 'part name'})
          w.save
          w.one = 456
          w.save
        end

        it 'should raise configuration error if incomplete' do
          expect { 
            class WidgetIncompleteConfig < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'

              attribute_control({}) do
                always_prevent_change :name
                allow_change_for 'one', { :attributes => [:one] }
                allow_change_for 'two', { :attributes => [:two, :three] }
              end
            end

            w = WidgetIncompleteConfig.new
            w.state = 'one'
            w.one = 123
            w.save
            w.one = 456
            w.save
          }.to raise_error(ChumpChange::ConfigurationError, /Missing control column/)
        end

        it 'should check that always_prevent_change attributes exist' do
          class WidgetConsistencyAlwaysPrevent < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent_change :namex
              allow_change_for 'one', { :attributes => [:one] }
              allow_change_for 'two', { :attributes => [:two, :three] }
            end
          end

          w = WidgetConsistencyAlwaysPrevent.new
          w.state = 'one'
          w.one = 123
          w.save

          expect {
            w.one = 456
            w.save
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid attributes.*always_prevent_change.*namex/)
        end

        it 'should check that allow_change_for attributes exist' do
          expect {
            class WidgetConsistencyAllowMod < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
            
              attribute_control({:control_by => :state}) do
                always_prevent_change :name
                allow_change_for 'one', { :attributes => [:onex] }
              end
            end
          
            w = WidgetConsistencyAllowMod.new
            w.state = 'one'
            w.one = 123
            w.save

            w.one = 456
            w.save
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid attributes.*allow_change_for.*onex/)
        end
        
        it 'should check that allow_change_for associations exist' do
          expect {
            class WidgetPartAssociationConfig < ActiveRecord::Base
              self.table_name = 'parts'
              belongs_to :widget
            end

            class WidgetConsistencyAssocConfig < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
              has_one :part
            
              attribute_control({:control_by => :state}) do
                always_prevent_change :name
                allow_change_for 'one', { :associations => { :partx => { :attributes => [:name]} } }
              end
            end

            w = WidgetConsistencyAssocConfig.new
            w.state = 'one'
            w.one = 123
            w.save

            w.one = 456
            w.save
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid association names specified.*partx/)
        end
        
        it 'should check that the control_by attribute exists' do
          expect {
            class WidgetConsistencyControlBy < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
            
              attribute_control({:control_by => :statex}) do
                always_prevent_change :name
                allow_change_for 'one', { :attributes => [:one] }
              end
            end
          
            w = WidgetConsistencyControlBy.new
            w.state = 'one'
            w.one = 123
            w.save

            w.one = 456
            w.save
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid control_by value.*statex/)
        end
      end

      context 'should prevent disallowed changes' do

        before(:each) do
          class WidgetChangesPreventDisallowed < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'
            has_one :part

            attribute_control({:control_by => :state}) do
              always_prevent_change :name
              allow_change_for 'initiated', { :attributes => [:one, :two, :three] }
              allow_change_for 'completed', { :attributes => [:four, :five] }
            end
          end

          class ::WidgetPartAssociationPrevent < ActiveRecord::Base
            self.table_name = 'parts'

            belongs_to :widget
          end
          
          class WidgetChangesPreventDisallowedWithMethod < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'
            has_one :part

            attribute_control({:control_by => :control_method}) do
              always_prevent_change :name
              allow_change_for 'INITIATED', { :attributes => [:one, :two, :three] }
              allow_change_for 'COMPLETED', { :attributes => [:four, :five] }
            end

            def control_method
              state.upcase if state
            end
          end
        end

        it 'should prevent changes to attributes explicitly prevented' do
          [WidgetChangesPreventDisallowed, WidgetChangesPreventDisallowedWithMethod].each_with_index do |klass, i|
            w = klass.new
            w.state = ['initiated', 'INITIATED'][i]  # deal with the different implementation in the second pass
            w.name = 'initial value'
            w.save

            w.name = 'altered value'
            expect {
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*name/) 

            # still no problems with a nil or unknown state (control value)
            w = klass.new
            w.name = 'initial value'
            w.save

            w.name = 'altered value'
            expect {
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*name/) 
          end
        end

        it 'should prevent modifications to attributes not listed for a given state' do
          w = WidgetChangesPreventDisallowed.new
          w.state = 'initiated'
          w.one = 1
          w.four = 4
          w.save

          w.four = 400 
          expect {
            w.save
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*four/) 
        end

        it 'should allow prevented changes within a without_attribute_control block' do
          obj = Class.new { include ChumpChange::Status }.new

          w = WidgetChangesPreventDisallowed.new
          w.state = 'initiated'
          w.one = 1
          w.four = 4
          w.save

          w.four = 400 
          obj.without_attribute_control {
            w.save
          }
        end

        context 'has_one relationship' do
          before(:each) do
            class WidgetChangesPreventDisallowedHasOne < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'

              has_one :part, :class_name => 'WidgetPartAssociationPrevent', :as => :widget

              attribute_control({:control_by => :state}) do
                always_prevent_change :name

                # while initiated - only allow creation/deletion of part -- but can only change quantity;  no model attributes may be changed
                allow_change_for 'initiated', { :associations => { :part => { :attributes => [:quantity] } } }
                prevent_change_for 'no_can_do'

                # when completed - no longer allow creation or deletion of a part; only allow :four and :five to be modified on model
                allow_change_for 'completed', {
                  :attributes => [:four, :five] ,
                  :associations => { :part => { :allow_create => false, :allow_delete => false } }
                }
              end
            end
          end

          it 'should prevent appropriate modification of model attributes' do
            w = WidgetChangesPreventDisallowedHasOne.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123

            w.part = ::WidgetPartAssociationPrevent.new({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            w.one -= 1
            expect {
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*one/) 

            w.state = 'no_can_do'
            expect {
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*one/) 
          end

          it 'should prevent creating associated record' do
            pending "Checking for creation of record not yet supported"

            w = WidgetChangesPreventDisallowedHasOne.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.save.should be_true

            w.part = ::WidgetPartAssociationPrevent.new({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            expect {
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to create association record on :parts/) 
          end

          it 'should prevent deleting associated record' do
            pending "Checking for deletion of record not yet supported"

            w = WidgetChangesPreventDisallowedHasOne.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.part = ::WidgetPartAssociationPrevent.new({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            expect {
              w.part = nil
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to delete association record on :parts/) 
          end

          it 'should prevent changes for associated record attributes' do
            w = WidgetChangesPreventDisallowedHasOne.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.part = ::WidgetPartAssociationPrevent.new({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            expect {
              w.part.name = 'altered'
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields on.*part.*name/) 
          end
        end

        context 'has_many relationship' do
          before(:each) do
            class WidgetChangesPreventDisallowedHasMany < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian

              after_initialize :setup_state

              self.table_name = 'widgets'
              has_many :parts, :class_name => 'WidgetPartAssociationPrevent', :as => :widget,
                :before_add => :original_before_add, :before_remove => :original_before_remove

              def setup_state
                @before_add_hook_called = false
                @before_remove_hook_called = false
              end

              def original_before_add(val)
                @before_add_hook_called = true
              end

              def original_before_remove(val)
                @before_remove_hook_called = true
              end

              def original_before_add_hook_called?
                @before_add_hook_called
              end

              def original_before_remove_hook_called?
                @before_remove_hook_called
              end

              attribute_control(:control_by => :state) do
                always_prevent_change :name

                # while initiated - only allow creation/deletion of part -- but can only change quantity;  no model attributes may be changed
                allow_change_for 'initiated', { :associations => { :parts => { :attributes => [:quantity] } } }

                prevent_change_for 'unladen_swallow'
                prevent_change_for 'african', 'european'
                prevent_change_for ['arrays', 'are', 'okay']

                # when completed - no longer allow creation or deletion of a part; only allow :four and :five to be modified on model
                allow_change_for 'completed', {
                  :attributes => [:four, :five] ,
                  :associations => { :parts => { :allow_create => false, :allow_delete => false } }
                }
              end
            end
            
            class ::WidgetPartAssociationUncontrolled < ActiveRecord::Base
              self.table_name = 'parts'

              belongs_to :widget
            end

            class WidgetChangesUncontrolledHasMany < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian

              self.table_name = 'widgets'
              has_many :parts, :class_name => 'WidgetPartAssociationUncontrolled', :as => :widget
                
              attribute_control(:control_by => :state) do
                always_prevent_change :name

                # no mention of association - should be wide open for change
                allow_change_for 'initiated', { :attributes => [:one, :two, :three] }
              end
            end

          end

          it 'should prevent adding to one-to-many' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'completed'
            w.one = w.two = w.three = 123
            w.save.should be_true

            expect {
              w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            }.to raise_error(ChumpChange::Error, /Attempt has been made to create association record on :parts/) 
          end

          it 'should prevent deleting from one-to-many' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'completed'
            w.one = w.two = w.three = 123
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.parts.build({:name => 'another test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            p = w.parts.where(:name => 'another test')
            p.should_not be_empty
            expect {
              w.parts.delete(p)
            }.to raise_error(ChumpChange::Error, /Attempt has been made to delete association record on :parts/) 
          end

          it 'should prevent changes for one-to-many associated record attributes' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.parts.build({:name => 'quick test2', :manufacturer_state => 'NC', :quantity => 20})
            w.save.should be_true

            expect {
              w.parts[1].name = 'altered'
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields on.*parts.*name/) 

            w.state = 'completed'
            w.parts[1].quantity = 123

            expect {
              w.save
            }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields on.*parts.*quantity/) 
          end

          it 'should execute before_add hooks as originally configured' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.save.should be_true

            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})

            w.original_before_add_hook_called?.should be_true
          end
          
          it 'should execute before_remove hooks as originally configured' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            w.parts.clear
            w.original_before_remove_hook_called?.should be_true
          end

          it 'should allow add to association as configured' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.save.should be_true

            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true   # no error
          end
          
          it 'should allow delete from association as configured' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            w.parts.clear
            w.save.should be_true
          end

          it 'should allow mods to association attributes as configured' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.one = w.two = w.three = 123
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            w.parts[0].quantity += 1
            w.save.should be_true
          end

          it 'should report appropriate fields allowed to be modified on associations' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            w.allowable_change_fields_for_parts.should == [:quantity]

            # prevented changes
            ['unladen_swallow', 'african', 'european', 'arrays', 'are', 'okay'].each do |st|
              w.state = st
              w.allowable_change_fields_for_parts.should == []
            end
            
            w.state = 'completed'
            w.allowable_change_fields_for_parts.should == ::WidgetPartAssociationPrevent.attribute_names
          end

          it 'should report appropriate fields allowed for uncontrolled association' do
            w = WidgetChangesUncontrolledHasMany.new
            w.state = 'initiated'

            w.allowable_change_fields_for_parts.sort.should == ::WidgetPartAssociationUncontrolled.attribute_names.sort
          end

          it 'should report appropriate available actions available for associations' do
            w = WidgetChangesPreventDisallowedHasMany.new
            w.state = 'initiated'
            w.parts.build({:name => 'quick test', :manufacturer_state => 'VA', :quantity => 100})
            w.save.should be_true

            w.allowable_operations_for_parts.should == [:create, :delete]
            
            # prevented changes
            ['unladen_swallow', 'african', 'european'].each do |st|
              w.state = st
              w.allowable_operations_for_parts.should == []
            end
            
            w.state = 'completed'
            w.allowable_operations_for_parts.should == []
          end

        end
      end

      context 'should allow model changes that have not been prevented' do
        def available_attributes_for(klass)
          klass.attribute_names.collect!{|attrib| attrib.to_sym} - [:created_at]
        end

        context 'configuration with multiple states' do
          before(:all) do
            class WidgetMultiStateConfiguration < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'

              attribute_control({:control_by => :state}) do
                always_prevent_change :name
                allow_change_for ['initiated','another_state'], { :attributes => [:one, :two, :three] }
                allow_change_for 'completed', { :attributes => [:four, :five] }
              end
            end
          end

          it 'should return appropriate values for multiple states configured at once' do
            w = WidgetMultiStateConfiguration.new
            ['initiated','another_state'].each do |st|
              w.state = st
              w.allowable_change_fields.sort.should == [:one, :two, :three, :state].sort
            end

            w.state = 'completed'
            w.allowable_change_fields.sort.should == [:four, :five, :state].sort
          end
        end

        context 'unmonitored control attribute value' do
          before(:each) do
            class WidgetNotControlled < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'

              attribute_control({:control_by => :state}) do
                always_prevent_change :name
                allow_change_for 'initiated', { :attributes => [:one, :two, :three] }
                allow_change_for 'completed', { :attributes => [:four, :five] }
              end
            end
          end

          it 'should allow changes for values of the control attribute that have not been configured' do
            w = WidgetNotControlled.new
            w.state = 'not_controlled'
            w.one = 1
            w.two = 2
            w.three = 3
            w.four = 4
            w.five = 5
            w.save

            w.one = 100
            w.two = 200
            w.three = 300
            w.four = 400
            w.five = 500
            w.save.should be_true
          end

          it 'should return appropriate fields allowed for change' do
            w = WidgetNotControlled.new
            w.state = 'not_controlled'
            w.one = 1
            w.two = 2
            w.three = 3
            w.four = 4
            w.five = 5
            w.save

            expected = (available_attributes_for(WidgetNotControlled)-[:name]).sort
            allowed = w.allowable_change_fields.sort
            expected.should == allowed
          end
        end

        context 'specified changes' do
          before(:each) do
            class WidgetAllowConfiguredChanges < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'

              attribute_control({:control_by => :state}) do
                always_prevent_change :name
                allow_change_for 'initiated', { :attributes => [:one, :two, :three] }
                allow_change_for 'completed', { :attributes => [:four, :five] }
              end
            end
          end

          it 'should allow changes to values specified in the allow_change_for configuration' do
            w = WidgetAllowConfiguredChanges.new
            w.state = 'initiated'
            w.one = 1
            w.two = 2
            w.three = 3
            w.four = 4
            w.five = 5
            w.save

            w.one = 100
            w.two = 200
            w.three = 300
            w.save.should be_true

            w.state = 'completed'
            w.four = 400
            w.five = 500
            w.save.should be_true
          end

          it 'should return appropriate fields allowed for change' do
            w = WidgetAllowConfiguredChanges.new
            w.state = 'initiated'
            w.save

            expected = [ :one, :two, :three, :state].sort
            allowed = w.allowable_change_fields.sort
            expected.should == allowed

            w.state = 'completed'
            expected = [ :four, :five, :state].sort
            allowed = w.allowable_change_fields.sort
            expected.should == allowed
          end

          it 'should include control column if explicitly indicated to do so' do
            w = WidgetAllowConfiguredChanges.new
            w.state = 'initiated'
            w.save

            expected = [ :one, :two, :three, :state].sort
            allowed = w.allowable_change_fields(:include_control_column=>true).sort
            expected.should == allowed

            w.state = 'completed'
            expected = [ :four, :five, :state].sort
            allowed = w.allowable_change_fields(:include_control_column=>true).sort
            expected.should == allowed
          end

          it 'should not include control column if indicated not to do so' do
            w = WidgetAllowConfiguredChanges.new
            w.state = 'initiated'
            w.save

            expected = [ :one, :two, :three ].sort
            allowed = w.allowable_change_fields(:include_control_column=>false).sort
            expected.should == allowed

            w.state = 'completed'
            expected = [ :four, :five ].sort
            allowed = w.allowable_change_fields(:include_control_column=>false).sort
            expected.should == allowed
          end
        end
      end
    end
  end
end
