require 'spec_helper'

module ChumpChange
  module AttributeGuardian
    describe 'AttributeGuardian' do
      
      before(:all) do
        ::ActiveRecord::Migration.create_table :widgets do |t|
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
          t.string :name
          t.string :manufacturer_state
          t.integer :quantity
          t.integer :widget_id
          t.timestamps
        end
      end

      after(:all) do
        ::ActiveRecord::Migration.drop_table :widgets
        ::ActiveRecord::Migration.drop_table :parts
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
                :associations => [ {
                                     :part => {     # allow_* default to true
                                        :allow_create => true,
                                        :allow_delete => false
                                     }
                                   }, 
                                   {
                                     :things => {
                                        :attributes => [ :city, :state ]
                                     }
                                   }
                                 ]
              }
            end
          end

          # When class loads, field consistency check executes
          WidgetSimpleBasedOnState
        end
         
        it 'should load with configuration that allows for association' do
          class WidgetPartAssociationConfig < ActiveRecord::Base
            self.table_name = 'parts'

            belongs_to :widget
          end

          class Widget < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            has_one :part

            attribute_control({:control_by => :state}) do
              always_prevent_change :name
              allow_change_for 'one', {
                 :attributes => [:one],
                 :associations => [
                    {
                      :part => {
                        :attributes => [ :name, :quantity ]
                      }
                    }
                 ]
              }
              allow_change_for 'two', {
                :attributes => [:two, :three]
              }
            end
          end
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
          }.to raise_error(ChumpChange::ConfigurationError, /Missing control column/)
        end

        it 'should check that always_prevent_change attributes exist' do
          expect {
            class WidgetConsistencyAlwaysPrevent < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
            
              attribute_control({:control_by => :state}) do
                always_prevent_change :namex
                allow_change_for 'one', { :attributes => [:one] }
                allow_change_for 'two', { :attributes => [:two, :three] }
              end
            end
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
                allow_change_for 'one', { :associations => [ {:partx => { :attributes => [:name]} } ] }
              end
            end
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
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid control_by attribute.*statex/)
        end
      end

      context 'should prevent disallowed changes' do

        before(:each) do
          class WidgetChangesPreventDisallowed < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent_change :name
              allow_change_for 'initiated', { :attributes => [:one, :two, :three] }
              allow_change_for 'completed', { :attributes => [:four, :five] }
            end
          end

          class WidgetPartAssociationPrevent < ActiveRecord::Base
            self.table_name = 'parts'

            belongs_to :widget
          end
        end

        it 'should prevent changes to attributes explicitly prevented' do
          w = WidgetChangesPreventDisallowed.new
          w.state = 'initiated'
          w.name = 'initial value'
          w.save

          w.name = 'altered value'
          expect {
            w.save
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*name/) 
          
          # still no problems with a nil or unknown state (control value)
          w = WidgetChangesPreventDisallowed.new
          w.name = 'initial value'
          w.save

          w.name = 'altered value'
          expect {
            w.save
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*name/) 
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

        it 'should prevent creating associated record' do
        end
        
        it 'should prevent deleting associated record' do
        end

        it 'should prevent changes for associated record attributes' do
        end
        
        it 'should prevent adding to one-to-many' do
        end

        it 'should prevent deleting from one-to-many' do
        end

        it 'should prevent changes for one-to-many associated record attributes' do
        end
      end

      context 'should allow changes that have not been prevented' do
        def available_attributes_for(klass)
          klass.attribute_names.collect!{|attrib| attrib.to_sym} - [:created_at, :updated_at]
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

        it 'should allow changes to values specified in the allow_change_for configuration' do
          class WidgetAllowConfiguredChanges < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent_change :name
              allow_change_for 'initiated', { :attributes => [:one, :two, :three] }
              allow_change_for 'completed', { :attributes => [:four, :five] }
            end
          end

          w = WidgetAllowConfiguredChanges.new
          w.state = 'not_controlled'
          w.one = 1
          w.two = 2
          w.three = 3
          w.four = 4
          w.five = 5
          w.save

          w.state = 'initiated'
          w.one = 100
          w.two = 200
          w.three = 300
          w.save.should be_true

          w.state = 'completed'
          w.four = 400
          w.five = 500
          w.save.should be_true
        end
      end
    end
  end
end
