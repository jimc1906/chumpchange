require 'spec_helper'

module ChumpChange
  module AttributeGuardian
    describe 'AttributeGuardin' do
      
      context 'AttributeGuardian testing' do
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
                allow_modification 'one', :onex
              end
            end
          }.to raise_error(ChumpChange::ConfigurationError, /Invalid control_by attribute.*statex/)
        end
      end
    end
  end
end
