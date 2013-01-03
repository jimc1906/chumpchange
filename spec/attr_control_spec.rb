require 'spec_helper'

module AttrControl
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
            include ::AttrControl::AttributeGuardian
            self.table_name = 'widgets'

            attribute_control({}) do
              always_prevent :name
              allow_modification 'one', :one
              allow_modification 'two', :two, :three
            end
          end

          # When class loads, field consistency check executes
          WidgetSimpleBasedOnState
        end

        it 'should check for consistency' do
          class WidgetConsistency < ActiveRecord::Base
            include ::AttrControl::AttributeGuardian
            self.table_name = 'widgets'
            
          end

          3.should == 3
          w = WidgetConsistency.new
          w.save
        end
      end
    end
  end
end
