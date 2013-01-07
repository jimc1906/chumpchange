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
      end

      after(:all) do
        ::ActiveRecord::Migration.drop_table :widgets
      end

      context 'should prevent invalid configuration' do
        it 'should load with configuration' do
          class WidgetSimpleBasedOnState < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent :name
              allow_modification 'one', :one
              allow_modification 'two', :two, :three
            end
          end

          # When class loads, field consistency check executes
          WidgetSimpleBasedOnState
        end

        it 'should raise configuration error if incomplete' do
          expect { 
            class WidgetIncompleteConfig < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'

              attribute_control({}) do
                always_prevent :name
                allow_modification 'one', :one
                allow_modification 'two', :two, :three
              end
            end
          }.to raise_error(ChumpChange::ConfigurationError, /Missing control column/)
        end

        it 'should check that always_prevent attributes exist' do
          expect {
            class WidgetConsistencyAlwaysPrevent < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
            
              attribute_control({:control_by => :state}) do
                always_prevent :namex
                allow_modification 'one', :one
                allow_modification 'two', :two, :three
              end
            end
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid attributes.*always_prevent.*namex/)
        end

        it 'should check that allow_modification attributes exist' do
          expect {
            class WidgetConsistencyAllowMod < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
            
              attribute_control({:control_by => :state}) do
                always_prevent :name
                allow_modification 'one', :onex
              end
            end
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid attributes.*allow_modification.*onex/)
        end
        
        it 'should check that the control_by attribute exists' do
          expect {
            class WidgetConsistencyControlBy < ActiveRecord::Base
              include ::ChumpChange::AttributeGuardian
              self.table_name = 'widgets'
            
              attribute_control({:control_by => :statex}) do
                always_prevent :name
                allow_modification 'one', :one
              end
            end
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid control_by attribute.*statex/)
        end
      end

      context 'should prevent disallowed changes' do

        it 'should prevent changes to attributes explicitly prevented' do
          class WidgetChangesAlwaysPrevent < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent :name
              allow_modification 'initiated', :one, :two, :three 
              allow_modification 'completed', :four, :five 
            end
          end

          w = WidgetChangesAlwaysPrevent.new
          w.name = 'initial value'
          w.save

          w.name = 'altered value'
          expect {
            w.save
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*name/) 
        end

        it 'should prevent modifications to attributes not listed for a given state' do
          class WidgetChangeNotAllowed < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent :name
              allow_modification 'initiated', :one, :two, :three 
              allow_modification 'completed', :four, :five 
            end
          end

          w = WidgetChangeNotAllowed.new
          w.state = 'initiated'
          w.one = 1
          w.four = 4
          w.save

          w.four = 400 
          expect {
            w.save
          }.to raise_error(ChumpChange::Error, /Attempt has been made to modify restricted fields.*four/) 

        end
      end

      context 'should allow changes that have not been prevented' do
        it 'should allow changes for values of the control attribute that have not been configured' do
          class WidgetNotControlled < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent :name
              allow_modification 'initiated', :one, :two, :three 
              allow_modification 'completed', :four, :five 
            end
          end

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

        it 'should allow changes to values specified in the allow_modification configuration' do
          class WidgetAllowConfiguredChanges < ActiveRecord::Base
            include ::ChumpChange::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({:control_by => :state}) do
              always_prevent :name
              allow_modification 'initiated', :one, :two, :three 
              allow_modification 'completed', :four, :five 
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
