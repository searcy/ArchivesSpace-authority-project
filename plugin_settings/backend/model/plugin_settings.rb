class PluginSettings < Sequel::Model(:plugin_settings)
  include ASModel
  corresponds_to JSONModel(:plugin_settings)

  set_model_scope :repository

  def self.init
	defs_file = File.join(File.dirname(__FILE__), '..', '..', "config", "plugin_settings_settings.rb")
    settings = {}
    if File.exists?(defs_file)
      found_defs_file = true
      Log.info("Loading Plugin Settings settings settings file at #{defs_file}")
      settings = eval(File.read(defs_file))
    else
		 Log.info("Plugin Settings settings file at #{defs_file} not found")
	end
    RequestContext.in_global_repo do
      filter = {:repo_id => Repository.global_repo_id, :user_id => nil}
      if self.filter(filter).count == 0
        Log.info("Creating system Plugin Settings")
        PluginSettings.create_from_json(JSONModel(:plugin_settings).from_hash({
                                                                       :user_id => nil,
                                                                       :settings => settings
                                                                     }),
                                    :repo_id => Repository.global_repo_id)
      else
        if found_defs_file
          Log.info("Updating system Plugin Settings")
          pref = self.filter(filter).first
          pref.update_from_json(JSONModel(:plugin_settings).from_hash({:settings => settings}),
                                :lock_version => pref.lock_version)
        end
      end
    end    
  end


  def before_save
    super
    self.user_uniq = self.user_id || 'GLOBAL_USER'
  end


  def after_save
    Notifications.notify("REFRESH_PLUGIN_SETTINGS")
  end


  def parsed_settings
    ASUtils.json_parse(self.settings)
  end


  def self.parsed_settings_for(filter)
    pref = self[filter.merge(:repo_id => RequestContext.get(:repo_id))]
    pref ? pref.parsed_settings : {}
  end


  def self.global_settings
    RequestContext.open(:repo_id => Repository.global_repo_id) do
      self.parsed_settings_for(:user_id => nil)
    end
  end


  def self.user_global_settings
    RequestContext.open(:repo_id => Repository.global_repo_id) do
      if RequestContext.get(:current_username)
        user_defs = self.parsed_settings_for(:user_id => User[:username => RequestContext.get(:current_username)].id)
        self.global_settings.merge(user_defs)
      else
        self.global_settings
      end
    end
  end


  def self.repo_settings
    self.user_global_settings.merge(self.parsed_settings_for(:user_id => nil))
  end


  def self.settings
    if RequestContext.get(:current_username)
      user_defs = self.parsed_settings_for(:user_id => User[:username => RequestContext.get(:current_username)].id)
      self.repo_settings.merge(user_defs)
    else
      self.repo_settings
    end
  end


  def self.current_plugin_settings(repo_id = RequestContext.get(:repo_id))
    return {} unless RequestContext.get(:current_username)

    user_id = User[:username => RequestContext.get(:current_username)].id
    filter = {:repo_id => repo_id, :user_uniq => [user_id.to_s, 'GLOBAL_USER']}
    json_prefs = {'settings' => {}}
    prefs = {}
    settings = {}

    if repo_id != Repository.global_repo_id
      self.filter(filter).each do |pref|
        if pref.user_uniq == 'GLOBAL_USER'
          json_prefs['repo'] = self.to_jsonmodel(pref)
          prefs[:repo] = pref
        else
          json_prefs['user_repo'] = self.to_jsonmodel(pref)
          prefs[:user_repo] = pref
        end
      end
    end
    RequestContext.in_global_repo do
      filter = {:repo_id => Repository.global_repo_id, :user_uniq => [user_id.to_s, 'GLOBAL_USER']}
      self.filter(filter).each do |pref|
        if pref.user_uniq == 'GLOBAL_USER'
          json_prefs['global'] = self.to_jsonmodel(pref)
          prefs[:global] = pref
        else
          json_prefs['user_global'] = self.to_jsonmodel(pref)
          prefs[:user_global] = pref
        end
      end
    end

    [:global, :user_global, :repo, :user_repo].each do |k|
      if prefs[k]
        json_prefs['settings'].merge!(prefs[k].parsed_settings)
        json_prefs["settings_#{k}"] = json_prefs['settings'].clone
      end
    end
    json_prefs['settings'].delete('jsonmodel_type')

	Log.debug(json_prefs)
    json_prefs
  end


  def self.sequel_to_jsonmodel(objs, opts = {})
    jsons = super

    jsons.zip(objs).each do |json, obj|
      json['settings'] = JSONModel(:settings).from_json(obj.settings)
    end

    jsons
  end


  def self.create_from_json(json, opts = {})
    super(json, opts.merge('settings' => JSON(json.settings || {})))
  end


  def update_from_json(json, opts = {}, apply_nested_records = true)
    super(json, opts.merge('settings' => JSON(json.settings)),
          apply_nested_records)
  end

end