# Base class for all LookupKeys descendants controllers
# The index method needs to be always implemented in the subclass
class LookupKeysController < ApplicationController
  include Foreman::Controller::AutoCompleteSearch
  before_action :setup_search_options, :only => :index
  before_action :find_resource, :only => [:edit, :update, :destroy], :if => proc { params[:id] }

  def edit
  end

  def update
    attributes = resource_params
    lookup_values = lookup_values_attributes(attributes)

    if resource.update(attributes.merge(:lookup_values_attributes => sanitize_attrs(lookup_values)))
      process_success
    else
      process_error
    end
  rescue JSON::ParserError
    resource.errors.add(:base, _('Override values payload is invalid'))
    process_error
  end

  def destroy
    if resource.destroy
      process_success
    else
      process_error
    end
  end

  protected

  def resource
    instance_variable_get("@#{resource_name}")
  end

  def resource_params
    send("#{resource_name}_params")
  end

  private

  def sanitize_attrs(attrs)
    to_delete, rest = attrs.partition { |_k, v| v["_destroy"] == "1" }.map { |arr| Hash[arr] }
    to_delete.each do |key, value|
      f_key, _value = rest.find { |_, f_value| f_value['match'] == value['match'] }
      unless f_key.nil?
        f_value = rest.delete f_key
        rest.update(key => value.merge(f_value))
      end
    end
    to_delete.merge(rest)
  end

  def lookup_values_attributes(attributes)
    payload = attributes.delete(:lookup_values_json)
    return attributes.fetch(:lookup_values_attributes, {}) if payload.blank?

    values = JSON.parse(payload)
    lookup_value_filter = self.class.lookup_value_params_filter.filter(nested_parameter_filter_context)
    values.transform_values do |value|
      ActionController::Parameters.new(value).permit(*lookup_value_filter).to_h
    end
  end

  def nested_parameter_filter_context
    Foreman::ParameterFilter::Context.new(:nested, controller_name, action_name)
  end

  def controller_permission
    'external_variables'
  end
end
