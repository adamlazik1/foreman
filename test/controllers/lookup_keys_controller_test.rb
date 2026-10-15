require 'test_helper'

class DummyLookupKey < LookupKey
end

class DummyLookupKeysController < LookupKeysController
  include Foreman::Controller::Parameters::LookupKey

  def self.dummy_lookup_key_params_filter
    Foreman::ParameterFilter.new(::DummyLookupKey).tap do |filter|
      add_lookup_key_params_filter(filter)
    end
  end

  def index
  end

  def process_error(hash = {})
    super(hash.merge(:render => { :plain => 'TaDa' }))
  end

  def dummy_lookup_key_params
    self.class.dummy_lookup_key_params_filter.filter_params(params, parameter_filter_context)
  end
end

Rails.application.routes.disable_clear_and_finalize = true
Rails.application.routes.draw do
  resources :dummy_lookup_keys
end

class LookupKeysControllerTest < ActionController::TestCase
  tests DummyLookupKeysController

  let(:key) { FactoryBot.create(:lookup_key, :integer, :type => 'DummyLookupKey') }
  let(:key_with_value) { FactoryBot.create(:lookup_key, :integer, :with_override, :path => "hostgroup\ncomment", :type => 'DummyLookupKey') }
  let(:new_value_params) { { 'match' => 'hostgroup=db', 'value' => '4', 'omit' => '0' } }
  let(:destroy_params) { { 'id' => key_with_value.override_values.first.id, '_destroy' => '1' } }

  test '#update adds valid override' do
    assert_equal key.override_values.count, 0
    params = { :override => true, :lookup_values_attributes => { '112' => new_value_params }}
    patch :update, params: { :id => key.to_param, :dummy_lookup_key => params }, session: set_session_user
    assert_redirected_to dummy_lookup_keys_path

    assert_equal key.reload.override_values.count, 1
    value = key.override_values.first
    assert_equal 'hostgroup=db', value.match
    assert_equal 4, value.value
  end

  test '#update passes more than 4096 overrides from JSON' do
    lookup_values = (0...4097).to_h do |index|
      [index.to_s, new_value_params.merge('match' => "hostgroup=group#{index}")]
    end
    params = { :override => true, :lookup_values_json => lookup_values.to_json }
    DummyLookupKey.any_instance.expects(:update).with do |attributes|
      assert_equal 4097, attributes[:lookup_values_attributes].size
      assert_equal new_value_params.merge('match' => 'hostgroup=group0'), attributes[:lookup_values_attributes]['0']
      true
    end.returns(true)

    patch :update, params: { :id => key.to_param, :dummy_lookup_key => params }, session: set_session_user

    assert_redirected_to dummy_lookup_keys_path
  end

  test '#update deletes values' do
    params = { :override => true, :lookup_values_attributes => { '0' => destroy_params }}
    assert_difference -> { key_with_value.override_values.count }, -1 do
      patch :update, params: { :id => key_with_value.to_param, :dummy_lookup_key => params }, session: set_session_user
      assert_redirected_to dummy_lookup_keys_path
    end
  end

  test '#update creates and deletes values simultanously' do
    params = { :override => true, :lookup_values_attributes => { '0' => destroy_params, '112' => new_value_params }}
    patch :update, params: { :id => key_with_value.to_param, :dummy_lookup_key => params }, session: set_session_user
    assert_redirected_to dummy_lookup_keys_path
    assert_equal key_with_value.reload.override_values.count, 1
    new_val = key_with_value.override_values.first
    assert_equal 4, new_val.value
    assert_equal 'hostgroup=db', new_val.match
  end

  test '#update handle match conflict' do
    lookup_values = { '112' => new_value_params, '113' => new_value_params, '0' => destroy_params }
    params = { :override => true, :lookup_values_json => lookup_values.to_json }
    patch :update, params: { :id => key_with_value.to_param, :dummy_lookup_key => params }, session: set_session_user
    assert_response :success
    assert_equal 1, key_with_value.reload.override_values.count
  end
end
