class User < ActiveRecord::Base
  
  # attr_accessible :facebook_id, :name, :email, :password, :password_confirmation, :authentications_attributes
  authenticates_with_sorcery! do |config|
    config.authentications_class = Authentication
  end
  
  has_many :authentications, :dependent => :destroy
  accepts_nested_attributes_for :authentications

  # validates_confirmation_of :password
  # validates_presence_of :password, :on => :create
  # validates_presence_of :email
  validates_uniqueness_of :email, :allow_nil => true, :allow_blank => true
  
  has_many :reviews
  has_many :comments
  has_many :likes
  
  mount_uploader :photo, ImageUploader
  
  def user_photo
    if photo.blank?
      ph = "http://graph.facebook.com/#{facebook_id}/picture?type=square" unless facebook_id.blank?
    else
      ph = "http://test.dish.fm#{photo.thumb.url}"
    end
    ph ||= ""
  end
  
  def self.get_user_by_fb_token(access_token) # Под снос! 
    begin
      rest = Koala::Facebook::GraphAndRestAPI.new(access_token) # pre-1.2beta
      result = rest.get_object("me")

      if user = User.find_by_facebook_id(result["id"])
        id = user.id
      elsif result["email"] 
        
        id = User.create({
          :email => result["email"] , 
          :name => result["name"], 
          :gender => result["gender"],
          :current_city => result["location"]["name"],
          :facebook_id => result["id"]
        }).id
        
        Authentication.create({
          :user_id => id,
          :provider => 'facebook',
          :uid => result["id"], 
        })
        User.new.get_user_fb_friends(access_token)        
      end
    rescue
      nil
    end
    id
  end
  
  def self.authenticate_by_twitter(oauth_token, oauth_token_secret, email = nil)
    begin
      client = Twitter::Client.new(:oauth_token => oauth_token, :oauth_token_secret => oauth_token_secret)
      if user = User.find_by_twitter_id(client.user.id)
        token = Session.get_token(user)
      else
        user = create_user_from_twitter(client, email)
        token = Session.get_token(user)        
      end
    rescue
      nil
    end
    {:name => user.name, :token => token, :user_id => user.id, :photo => user.user_photo, :facebook_id => user.facebook_id ||= 0, :twitter_id => user.twitter_id ||= 0} unless token.nil?
  end
  
  def self.create_user_from_twitter(client, email)
    user = User.create({
      :name => client.user.name,
      :email => email,  
      :twitter_id => client.user.id,
      :remote_photo_url => client.profile_image
    })
    
    # User.get_user_tw_friends(client.user.id)
    user
  end
  
  def self.authenticate_by_facebook(access_token)
    begin
      
      rest = Koala::Facebook::GraphAndRestAPI.new(access_token) # pre-1.2beta
      result = rest.get_object("me")

      if user = User.find_by_facebook_id(result["id"])
        token = Session.get_token(user)
        user.fb_access_token = access_token
        user.save
      elsif result["email"] 
        user = create_user_from_facebook(rest)
        token = Session.get_token(user)        
      end
    rescue
      nil
    end
    {:name => user.name, :token => token, :user_id => user.id, :photo => user.user_photo, :facebook_id => user.facebook_id, :twitter_id => user.twitter_id} unless token.nil? 
  end
  
  def self.create_user_from_facebook(rest)
    auth_result = rest.get_object("me")
    
    user = User.create({
      :email => auth_result["email"] , 
      :name => auth_result["name"], 
      :gender => auth_result["gender"],
      :current_city => auth_result["location"] ? auth_result["location"]["name"] : '',
      :facebook_id => auth_result["id"],
      :fb_access_token => rest.access_token
    })
    
    Authentication.create({
      :user_id => id,
      :provider => 'facebook',
      :uid => auth_result["id"], 
    })
    
    rest.get_connections("me", "friends").each do |f|
      if user_friend = User.find_by_facebook_id(f['id'])
        Notification.push(user.id, 'new_fb_user', user_friend.id)
      end
    end
    
    user
  end
    
  def get_user_fb_token(code)
    key = Dishfm::Application.config.sorcery.facebook.key
    secret = Dishfm::Application.config.sorcery.facebook.secret
    callback_url = Dishfm::Application.config.sorcery.facebook.callback_url
    
    oauth = Koala::Facebook::OAuth.new(key, secret, callback_url)
    begin
      access_token = oauth.get_access_token(code)
    rescue
      nil
    end
  end
  
  def self.get_user_fb_friends(code_or_access_token)
    if code_or_access_token
      if User.new.get_user_fb_token(code_or_access_token)
        access_token = User.new.get_user_fb_token(code_or_access_token)
      else
        access_token = code_or_access_token         
      end
    end
    system "rake get_facebook_friends ACCESS_TOKEN='#{access_token}' &" if access_token
  end
  
  def self.get_user_tw_friends(user_id)
    system "rake get_twitter_friends USER=#{user_id} &" if user_id
  end
  

  
end