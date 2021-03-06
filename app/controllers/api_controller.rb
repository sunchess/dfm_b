# encoding: utf-8
class ApiController < ApplicationController
  
  before_filter :init_error
  helper :all
  
  def init_error
    $error = {:description => nil, :code => nil}
  end
  
  def get_favourite_restaurants
    if params[:user_id]
      if user = User.find_by_id(params[:user_id])
      
        num_images = 20
         
        lat = params[:lat] ||= '55.753548'
        lon = params[:lon] ||= '37.609239'
        
        favourite_restaurants_ids = []
        favourite_delivery_ids = []
      
        Favourite.where(:user_id => params[:user_id]).each do |f|
          if !f.restaurant_id.nil?
            favourite_restaurants_ids.push(f.restaurant_id)
          elsif !f.delivery_id.nil?
            favourite_delivery_ids.push(f.delivery_id)
          end
        end
      
        networks = []
        if favourite_delivery_ids.any?
          
          delivery = Delivery.select('deliveries.photo, deliveries.fsq_id, deliveries.id, deliveries.name, deliveries.address, deliveries.city, deliveries.lat, deliveries.lon, deliveries.rating, deliveries.votes').where("deliveries.id in (#{favourite_delivery_ids.join(',')})").order('deliveries.updated_at DESC')
      
          delivery.each do |r|
            dishes = []    
            dishes_w_img = r.dish_deliveries.select('DISTINCT dish_deliveries.id, dish_deliveries.name, dish_deliveries.photo, dish_deliveries.rating, dish_deliveries.votes, dish_deliveries.dish_type_id').order("(dish_deliveries.rating - 3)*dish_deliveries.votes DESC, dish_deliveries.photo DESC").includes(:reviews).where("dish_deliveries.photo IS NOT NULL OR (dish_deliveries.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images)
    
            dishes_w_img.each do |dish|
              favourite = Favourite.find_by_user_id_and_dish_id(user.id, dish.id) ? 1 : 0
              
              dishes.push({
                :id => dish.id,
                :name => dish.name,
                :photo => dish.image_sd,
                :rating => dish.rating,
                :votes => dish.votes,
                :favourite => favourite
              })
            end
            networks.push({:favourite => 1, :network_id => r.id, :dishes => dishes, :type => 'delivery', :venues => r.fsq_id ? ["#{r.fsq_id}"] : []})
          end    
        end
      
        if favourite_restaurants_ids.any?
          
          restaurants = Restaurant.joins("LEFT OUTER JOIN `networks` ON `networks`.`id` = `restaurants`.`network_id` JOIN (
          #{Restaurant.select('id, address').where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL').order('restaurants.fsq_checkins_count DESC').to_sql}) r1
          ON `restaurants`.`id` = `r1`.`id`").where("restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL AND restaurants.id in (#{favourite_restaurants_ids.join(',')})").order('restaurants.updated_at DESC').group('restaurants.name')

          restaurants.select('restaurants.id, restaurants.name, restaurants.address, restaurants.city, restaurants.lat, restaurants.lon, restaurants.rating, restaurants.votes, restaurants.network_id, restaurants.fsq_id')  

          restaurants.each do |r|
            dont_add = 0
            networks.each do |n|
              dont_add = 1 && break if r.network_id == n[:network_id]
            end
            if dont_add == 0
              dishes = []
              dishes_w_img = r.network.dishes.select('DISTINCT dishes.id, dishes.name, dishes.photo, dishes.rating, dishes.votes, dishes.dish_type_id').order("(dishes.rating - 3)*dishes.votes DESC, dishes.photo DESC").includes(:reviews).where("dishes.photo IS NOT NULL OR (dishes.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images)

              dishes_w_img.each do |dish|
                favourite = Favourite.find_by_user_id_and_dish_id(user.id, dish.id) ? 1 : 0
                
                dishes.push({
                  :id => dish.id,
                  :name => dish.name,
                  :photo => dish.image_sd,
                  :rating => dish.rating,
                  :votes => dish.votes,
                  :favourite => favourite
                })
              end

              networks.push({:favourite => 1, :network_id => r.network_id, :dishes => dishes, :type => nil, :venues => r.fsq_id ? ["#{r.fsq_id}"] : []}) 
            end
          end
        end
      end
      
      if restaurants
        if restaurants.first.class.name == 'Delivery'
          delivery = restaurants
          restaurants = nil
        end
      end
      
    else
      $error = {:description => 'Params missing', :code => 26}
    end  
      
    return render :json => {
          :load_additional => load_additional ||= 0,
          :restaurants => restaurants ? restaurants.as_json({:keyword => params[:keyword] ||= nil}) : [],
          :deliveries => delivery ? delivery.as_json : [],
          :networks => networks,
          :error => $error
    }
  end
  
  def get_favourite_dishes
    if params[:user_id]
      lat = params[:lat] ||= '55.753548'
      lon = params[:lon] ||= '37.609239'
      
      if user = User.find_by_id(params[:user_id])
        dishes_array = user.favourite_dishes(params[:user_id])
        restaurants_array = Restaurant.for_dish_expert(dishes_array, lat, lon) if dishes_array.any?
      end
    else
      $error = {:description => 'Params missing', :code => 26}
    end
    return render :json => {
            :dishes => dishes_array || nil,
            :restaurants => restaurants_array || nil,
            :error => $error
    }
  end
  
  
  def get_pinterest_share_url
    domain = 'dish.fm'
    require 'cgi'
    
    if params[:review_id]
      if params[:self] == '1'
        if rw = Dish.find_by_id(params[:review_id])
          url = CGI.escape("http://#{domain}/dishes/#{rw.id}").gsub("+", "%20")
          media = CGI.escape("http://#{domain}#{rw.photo.iphone_retina.url}").gsub("+", "%20")
          text = CGI.escape("#{rw.name}@#{rw.network.name} via www.dish.fm").gsub("+", "%20")                    
          share_url = "http://m.pinterest.com/pin/create/button/?url=#{url}&media=#{media}&description=#{text}" 
        end
      elsif rw = Review.find_by_id(params[:review_id])
        url = CGI.escape("http://#{domain}/reviews/#{rw.id}").gsub("+", "%20")
        media = CGI.escape("http://#{domain}#{rw.photo.iphone_retina.url}").gsub("+", "%20")

        case rw.rtype
        when 'home_cooked'
          dish_name = rw.home_cook.name
          restaurant_name = 'Home-cooked'
        when 'delivery'
          dish_name = rw.dish_delivery.name
          restaurant_name = rw.delivery.name 
        else
          dish_name = rw.dish.name
          restaurant_name = rw.restaurant.name
        end
        
        if rw.text.blank?
          text = "#{dish_name}@#{restaurant_name} via www.dish.fm"
        else
          text = "#{rw.text[0 .. 240]} - #{dish_name}@#{restaurant_name} via www.dish.fm"
        end
        text = CGI.escape(text).gsub("+", "%20")
        
        share_url = "http://m.pinterest.com/pin/create/button/?url=#{url}&media=#{media}&description=#{text}"        
      else
        $error = {:description => 'Review not found', :code => 17}
      end
      
    elsif params[:restaurant_id]
      if rt = Restaurant.find_by_id(params[:restaurant_id])

        url = CGI.escape("http://#{domain}/restaurants/#{rt.id}").gsub("+", "%20")
        media = CGI.escape("http://#{domain}#{rt.thumb}").gsub("+", "%20")
        text = CGI.escape("#{rt.name} via www.dish.fm").gsub("+", "%20")
        
        share_url = "http://m.pinterest.com/pin/create/button/?url=#{url}&media=#{media}&description=#{text}"
      else
        $error = {:description => 'Restaurant not found', :code => 23}
      end
      
    else
      $error = {:description => 'Params missing', :code => 26}
    end
    
    return render :json => {
      :url => share_url,
      :error => $error
    }
  end
  
  def recover_password
    if params[:email]
      if user = User.find_by_email(params[:email])
        UserMailer.email_password_recover(user).deliver
      else
        $error = {:description => 'User not found', :code => 16}
      end
    else
      $error = {:description => 'Params missing', :code => 19}
    end
    return render :json => {
      :error => $error
    }
  end
  
  def logout
    if Session.check_token(params[:user_id], params[:token]) && params[:push_token]
      User.link_push_token(params[:push_token], params[:user_id])
      
      if device = APN::Device.find_by_token_and_user_id(params[:push_token],params[:user_id])
        device.active = 0
        device.save
      end
    end
    return render :json => {:error => $error}
  end
  
  def add_to_favourite
    if Session.check_token(params[:user_id], params[:token]) && (params[:dish_id] || params[:restaurant_id] || params[:delivery_id] || params[:home_cook_id] || params[:dish_delivery_id])
      if !params[:restaurant_id].blank?
        if f = Favourite.find_by_user_id_and_restaurant_id(params[:user_id], params[:restaurant_id])
          f.destroy
        else
          if restaurant = Restaurant.find_by_id(params[:restaurant_id])
            network_id = restaurant.network_id
            restaurant_id = restaurant.id
          end
        end
      elsif !params[:dish_id].blank?    
        if f = Favourite.find_by_user_id_and_dish_id(params[:user_id], params[:dish_id])
          f.destroy
        else
          if dish = Dish.find_by_id(params[:dish_id])
            dish_id = dish.id
          end
        end
      elsif !params[:delivery_id].blank?
        if f = Favourite.find_by_user_id_and_delivery_id(params[:user_id], params[:delivery_id])
          f.destroy
        else   
          if delivery = Delivery.find_by_id(params[:delivery_id])       
            delivery_id = delivery.id
          end
        end
      elsif !params[:dish_delivery_id].blank?
        if f = Favourite.find_by_user_id_and_dish_delivery_id(params[:user_id], params[:dish_delivery_id])
          f.destroy
        else
          if dish_delivery = DishDelivery.find_by_id(params[:dish_delivery_id])
            dish_delivery_id = dish_delivery.id
          end
        end
      elsif !params[:home_cook_id].blank?
        if f = Favourite.find_by_user_id_and_home_cook_id(params[:user_id], params[:home_cook_id])
          f.destroy
        else
          if home_cook = HomeCook.find_by_id(params[:home_cook_id])              
            home_cook_id = home_cook.id
          end
        end
      end
      
      if dish_id || restaurant_id || delivery_id || dish_delivery_id || home_cook_id
        Favourite.create(
          :user_id => params[:user_id].to_i,
          :dish_id => dish_id,
          :restaurant_id => restaurant_id,
          :delivery_id => delivery_id,
          :dish_delivery_id => dish_delivery_id,
          :home_cook_id => home_cook_id,
          :network_id => network_id ||= nil
        )
        system "rake facebook:save DISH_ID='#{dish_id}' USER_ID='#{params[:user_id]}' &" if dish_id
        system "rake facebook:save RESTAURANT_ID='#{restaurant_id}' USER_ID='#{params[:user_id]}' &" if restaurant_id
      end
    else
      $error = {:description => 'Params missing', :code => 155}  
    end
    
    return render :json => {
      :error => $error
    }
  end
  
  def set_user_preferences
    if Session.check_token(params[:user_id], params[:token])
      if pref = UserPreference.find_by_user_id(params[:user_id])
        
        params.each do |k,v|     
          pref.send("#{k}=".to_sym, v) if ActiveRecord::Base.connection.column_exists?(:user_preferences, k)
        end
        pref.save
    
      else  
        $error = {:description => 'User Preferences not found', :code => 21}
      end
        
    else
      $error = {:description => 'Params missing', :code => 25}
    end
    
    return render :json => {
      :error => $error
    }
  end
  
  def add_restaurant
    if params[:delivery].to_i == 1 && (params[:restaurant][:phone] || params[:restaurant][:web])
      if delivery = Delivery.create(params[:restaurant])
        r_id = delivery.id 
      end
    elsif (params[:restaurant][:address] || (params[:restaurant][:lat] && params[:restaurant][:lon]) || params[:restaurant][:web] || params[:restaurant][:phone]) && params[:restaurant][:name] && params[:restaurant][:category]
      
      if restaurant_category = RestaurantCategory.find_by_name(params[:restaurant][:category]) #TODO: make an array with categories not only single one
        params[:restaurant][:restaurant_categories] = restaurant_category.id
      else
        params[:restaurant][:restaurant_categories] = RestaurantCategory.create({:name => params[:restaurant][:category]}).id
      end
      params[:restaurant].delete(:category)
      
      n = Network.create({:name => params[:restaurant][:name], :city => params[:restaurant][:city]})
      params[:restaurant][:network_id] = n.id
      
      if params[:restaurant][:address]
        r = Geocoder.search("#{params[:restaurant][:address]}")
        unless r.blank?
          if params[:restaurant][:lat].blank? && params[:restaurant][:lon].blank?
            params[:restaurant][:lat] = r[0].geometry['location']['lat']
            params[:restaurant][:lon] = r[0].geometry['location']['lng']
          end
        end
      end
      
      if params[:restaurant][:lat] && params[:restaurant][:lon]
        r = Geocoder.search("#{params[:restaurant][:lat]},#{params[:restaurant][:lon]}")
        unless r.blank?
          if params[:restaurant][:address].blank?
            params[:restaurant][:address] = "#{r[0].address_components[1]['long_name']}, #{r[0].address_components[0]['long_name']}"
          end
        end
      end
      
      unless r.blank?
        if city = r[0].address_components[3]
          if city['long_name'] == 'Moscow'
            params[:restaurant][:city] = city['long_name']
          else
            params[:restaurant][:city] = r[0].address_components[2]['long_name']
          end
        else
          params[:restaurant][:city] = r[0].address_components[1]['long_name']
        end
      end
            
      params[:restaurant][:source] = 'user'      
      if rest = Restaurant.create(params[:restaurant])
        r_id = rest.id 
      end
          
    else
      $error = {:description => 'Params missing', :code => 8}
    end
    
    return render :json => {
          :error => $error,
          :restaurant_id => r_id ||= 0
    }
    
  end
  
  def add_social_network_account
    
    if Session.check_token(params[:user_id], params[:token]) && (params[:access_token] || (params[:oauth_token] && params[:oauth_token_secret]))
      user = User.find_by_id(params[:user_id])
      
      unless params[:access_token].blank?
        if rest = Koala::Facebook::GraphAndRestAPI.new(params[:access_token])
          result = rest.get_object("me")
          
          if old_user = User.find_by_facebook_id(result["id"])
            if user.id != old_user.id
              User.migrate(old_user,user)
              user.fb_valid_to = old_user.fb_valid_to
            end
          end
          
          # fb
          user.fb_access_token = params[:access_token]
          user.facebook_id = result["id"]                    
          user.email = result["email"]
          user.name = result["name"]
          user.gender = result["gender"]
          user.current_city = result["location"] ? result["location"]["name"] : ''
          
          # twitter
          user.oauth_token_secret = old_user.oauth_token_secret if user.oauth_token_secret.blank?
          user.oauth_token = old_user.oauth_token if user.oauth_token.blank?        
          user.twitter_id = old_user.twitter_id if user.twitter_id.blank?  
          
          user.save
        end
      end
      
      if !params[:oauth_token_secret].blank? && !params[:oauth_token].blank?
        if client = Twitter::Client.new(:oauth_token => params[:oauth_token], :oauth_token_secret => params[:oauth_token_secret])          
          if old_user = User.find_by_twitter_id(client.user.id)                        
            User.migrate(old_user,user) if user.id != old_user.id
          end
          
          # twitter
          user.oauth_token_secret = params[:oauth_token_secret]
          user.oauth_token = params[:oauth_token]          
          user.twitter_id = client.user.id
          
          # fb
          user.fb_access_token = old_user.fb_access_token if user.fb_access_token.blank?
          user.facebook_id = old_user.facebook_id if user.facebook_id.blank?                
          user.email = old_user.email if user.email.blank?
          user.name = old_user.name if user.name.blank?
          user.gender = old_user.gender if user.gender.blank?
          user.current_city = old_user.current_city if user.current_city.blank?
          
          user.save
        end
      end
      
    else
      $error = {:description => 'Params missing', :code => 8}
    end
    
    return render :json => {
          :error => $error
    }
  end
  
  def find_friends
    if params[:user_id] && (params[:access_token] || (params[:oauth_token] && params[:oauth_token_secret]))
      data = []
      
      if (params[:access_token])
        rest = Koala::Facebook::GraphAPI.new(params[:access_token])
        user = rest.get_object("me")

        rest.get_connections("me", "friends").each do |f|
          if user = User.select([:id, :name, :photo, :facebook_id]).find_by_facebook_id(f['id'])
            data.push(
              :id => user.id,
              :name => user.name,
              :photo => user.user_photo,
              :use => 1,
              :twitter => 0,
              :facebook => user.facebook_id.to_s
            )
          else
            data.push(
              :id => 0,
              :name => f['name'],
              :photo => "http://graph.facebook.com/#{f['id']}/picture?type=square",
              :use => 0,
              :twitter => 0,
              :facebook => f['id']
            )
          end
        end
      end
      
      if (params[:oauth_token] && params[:oauth_token_secret])
        if client = Twitter::Client.new(:oauth_token => params[:oauth_token], :oauth_token_secret => params[:oauth_token_secret])

          client.follower_ids.ids.each do |id|
            dont_push = 0
            if user = User.select([:id, :name, :photo, :twitter_id, :facebook_id]).find_by_twitter_id(id)
              data.each do |d|
                if d[:id] == user.id
                  d[:twitter] = user.twitter_id.to_s
                  dont_push = 1
                  break
                end
              end
              data.push({
                :id => user.id,
                :name => user.name,
                :photo => user.user_photo,
                :use => 1,
                :twitter => user.twitter_id.to_s,
                :facebook => 0
              }) if dont_push == 0
            end
          end

          client.friend_ids.ids.each do |id|
            if user = User.select([:id, :name, :photo, :twitter_id, :facebook_id]).find_by_twitter_id(id)
              dont_push = 0
              data.each do |d|
                if d[:id] == user.id
                  d[:twitter] = 1
                  dont_push = 1
                  break
                end
              end
              data.push({
                :id => user.id,
                :name => user.name,
                :photo => user.user_photo,
                :use => 1,
                :twitter => user.twitter_id.to_s,
                :facebook => 0
              }) if dont_push != 1
            end
          end
        end      
      end
      
    else
      $error = {:description => 'Params missing', :code => 8}
    end
    return render :json => {
          :users => data,
          :error => $error
    }
  end
  
  def add_push_token
    if params[:push_token]
      APN::Device.create(:token => params[:push_token]) unless APN::Device.where(:token => params[:push_token]).first
    else
      $error = {:description => 'Params missing', :code => 8}
    end
    return render :json => {
          :error => $error
    }
  end
  
  def get_user_following
    if params[:user_id]
      following = []
      User.select([:id, :photo, :name, :facebook_id]).where('id IN (SELECT follow_user_id FROM followers WHERE user_id = ?)', params[:user_id]).order(:name).each do |f|
        following.push({
          :user_id => f.id,
          :name => f.name,
          :photo => f.user_photo
        })
      end
      followers =  []
      User.select([:id, :photo, :name, :facebook_id]).where('id IN (SELECT user_id FROM followers WHERE follow_user_id = ?)', params[:user_id]).order(:name).each do |f|
          followers.push({
            :user_id => f.id,
            :name => f.name,
            :photo => f.user_photo
          })
      end
    else
      $error = {:description => 'Params missing', :code => 8}
    end
    
    return render :json => {
          :following => following ||= [],
          :followers => followers ||= [],
          :error => $error
    }
  end
  
  def del_comment
    if params[:comment_id] && Session.check_token(params[:user_id], params[:token])
      if params[:self_review].to_i == 1
        if comment = DishComment.find_by_id_and_user_id(params[:comment_id], params[:user_id])
          comment.delete
        else
          $error = {:description => 'Comment not found', :code => 5}
        end
      else
        if comment = Comment.find_by_id_and_user_id(params[:comment_id], params[:user_id])
          comment.delete
        else
          $error = {:description => 'Comment not found', :code => 5}
        end
      end
    else
        $error = {:description => 'Params missing', :code => 8}
    end
    return render :json => {
          :error => $error
    }
  end
  
  def del_review
    if params[:review_id] && Session.check_token(params[:user_id], params[:token])   
        if review = Review.find_by_id_and_user_id(params[:review_id], params[:user_id])
          review.delete
        else
          $error = {:description => 'Review not found', :code => 329}  
        end
    else
        $error = {:description => 'User or Review not found', :code => 332}
    end
    return render :json => {
          :error => $error
    }
  end
  
  def authenticate_user
    if params[:provider]  
      if params[:provider] == 'facebook' && params[:access_token]
        session = User.authenticate_by_facebook(params[:access_token], params[:fb_valid_to]) 
      elsif params[:provider] == 'twitter' && params[:oauth_token] && params[:oauth_token_secret]
        session = User.authenticate_by_twitter(params[:oauth_token], params[:oauth_token_secret], params[:email])
      end      
    elsif params[:email] && params[:password]
      session = User.authenticate_by_email_password(params[:email], params[:password], params[:name])
      
      if session[:user_id]
        user_preferences = UserPreference.for_user.find_by_user_id session[:user_id]
      else
        $error = {:description => session[:description], :code => 367}
      end
      
    else
      $error = {:description => 'Parameters missing', :code => 370}
    end
    
    if session
      if params[:push_token] && session[:user_id]
        
        #Add push token
        User.link_push_token(params[:push_token], session[:user_id])
        
        #Alow send pushes on login
        if device = APN::Device.find_by_token_and_user_id(params[:push_token], session[:user_id])
          device.active = 1
          device.save
        end
      end
      user_preferences = UserPreference.for_user.find_by_user_id session[:user_id]
    end
    
    return render :json => {
          :session => session && session[:user_id] ? session : nil,
          :user_preferences => user_preferences ||= nil,
          :error => $error
    }
  end
  
  def follow_user
    if Session.check_token(params[:user_id], params[:token]) && !params[:follow_user_id].blank?
      
      params[:follow_user_id].split(',').each do |fu|
        if fu != params[:user_id]
        
          if follower = Follower.find_by_user_id_and_follow_user_id(params[:user_id], fu)
            follower.destroy
          else
            Follower.create({:user_id => params[:user_id], :follow_user_id => fu})
            Notification.send(params[:user_id], 'following', fu)
          end
          
        end
      end
      
    end
    return render :json => {:error => $error}
  end
  
  def get_dish
    if params[:dish_id]
      return render :json => API.get_dish(params[:user_id], params[:dish_id], params[:type], params[:found])
    else
      $error = {:description => 'Parameters missing', :code => 8}
      return render :json => {:error => $error}
    end
  end
  
  def get_common_data
    timestamp = Time.at(params[:timestamp].to_i) if params[:timestamp].to_i > 0
            
    keywords = Tag.select("id, name_a as name").where("name_a IN ('steak','salad','soup','pasta','pizza','burger','sushi','dessert','drinks','meat','fish','vegetables')").order("`order`")
    locations = LocationTip.select([:id, :name])
    rc = RestaurantCategory.select([:name]).where("active = 1 AND name IS NOT NULL")

    return render :json => {
          :types => DishType.format_for_api(timestamp),
          :keywords => timestamp ? keywords.where('updated_at >= ?', timestamp) : keywords,
          :restaurant_categories => timestamp ? rc.where('updated_at >= ?', timestamp) : rc,
          # :cities => timestamp ? locations.where('updated_at >= ?', timestamp) : locations.all,
          :tags => Tag.get_all(timestamp),
          :force_logout => 0,
          :error => $error,
    }
  end
  
  def get_restaurant
    if params[:restaurant_id] || params[:network_id]
      if params[:restaurant_id]
        id = params[:restaurant_id]
        data_type = 'restaurant'
      else
        id = params[:network_id]
        data_type = 'network'
      end     
      return render :json => API.get_restaurant(id, data_type, params[:user_id], params[:type], params[:found])
    else
      return render :json => {:error => $error}
    end
  end
  
  def get_dishes
    
    lat = params[:lat] ||= '55.753548'
    lon = params[:lon] ||= '37.609239'
    
    top_user_id = params[:top_user_id].to_i
    current_user_id = params[:user_id].to_i
    favourite = 0    
    
    if top_user_id > 0
      
      if user = User.find_by_id(top_user_id)
        dishes_array = user.dish_expert(current_user_id)
        restaurants_array = Restaurant.for_dish_expert(dishes_array, lat, lon) if dishes_array.any?
      end
      
    else    
      
      if params[:radius].to_f != 0 
        radius = params[:radius].to_f
      else
        radius = 30 if params[:radius] == 'city'
        radius = 40075 if params[:radius] == 'global'
      end
    
      if radius
      
        limit = 25
        
        bill = params[:bill] || ''
        networks = []
        
        restaurants = Restaurant.select(:network_id).near(params[:lat], params[:lon], radius).group(:network_id)
        restaurants = restaurants.bill(bill) if bill.to_i != 0 && bill != '11111'
          
        if params[:type] == 'home_cooked'
          dishes = HomeCook.select([:id, :name, :rating, :votes, :photo]).order("votes DESC, photo DESC")
        elsif params[:type] == 'delivery'
          restaurants = restaurants.where(:delivery => 1)
          restaurants.each {|r| networks.push(r.network_id)}
          
          dishes = DishDelivery.select([:id, :name, :rating, :votes, :photo, :price, :currency, :delivery_id]).order("votes DESC, photo DESC")
          dishes = dishes.where("delivery_id IN (#{networks.join(',')})") if networks.any?
        else    
          if restaurants.any?
            restaurants.each {|r| networks.push(r.network_id)}
            
            dishes = Dish.select([:id, :name, :rating, :votes, :photo, :network_id, :price, :currency, :fsq_checkins_count]).order("votes DESC, photo DESC, fsq_checkins_count DESC")
            dishes = dishes.where("network_id IN (#{networks.join(',')})") if networks.any?
            dishes = dishes.search_by_tag_id(params[:tag_id]) if params[:tag_id].to_i > 0
            dishes = dishes.search(params[:search]) unless params[:search].blank?
          end
        end
        
        if dishes
          if params[:dish_id] && params[:dish_id].to_i > 0
      
            if params[:type] == 'home_cooked'
              dish = HomeCook.select([:id, :rating]).where(:id => params[:dish_id].to_i)
            elsif params[:type] == 'delivery'
              dish = DishDelivery.select([:id, :rating]).where(:id => params[:dish_id].to_i)
            else
              dish = Dish.select([:id, :rating, :fsq_checkins_count]).where(:id => params[:dish_id].to_i)            
            end
      
            unless dish.nil?
              dish = dish.search_by_tag_id(params[:tag_id]) if params[:tag_id].to_i > 0
              dish = dish.first
              rating = dish.rating
        
              if params[:type] != 'home_cooked' && params[:type] != 'delivery'
                fsq_checkins_count = dish.fsq_checkins_count if dish.fsq_checkins_count > 0
              end

            end
          end

          if rating.nil?
            start = 1
            rating = 5
          else
            start = 0
          end
          dishes_array = []

          if rating && rating > 0
            step = 0.25  
            (0..(5-step)).step(step) do |n|
                n1 = 5 - n
                n2 = n1 - step != 0 ? n1 - step : 0
                if (rating > n2 && rating <= n1) || (rating > n2 && rating > n1 && dishes_array.count < limit)
          
                  start = 1 if rating > n2 && rating > n1 && dishes_array.count < limit
                  if dishes_between = dishes.where("rating > ? AND rating <= ?", n2, n1)
            
                    dishes_between.each do |d|
                      if start == 1
                        if dishes_array.count < limit
                          favourite = Favourite.find_by_user_id_and_dish_id(current_user_id, d.id) ? 1 : 0
                          network_data = Network.select([:id, :name]).find_by_id(d.network_id) if params[:type] != 'home_cooked' && params[:type] != 'delivery' 
                          dishes_array.push({
                            :id => d.id,
                            :name => d.name,
                            :rating => d.rating,
                            :votes => d.votes,
                            :price => params[:type] == 'home_cooked' ? 0 : d.price,
                            :currency => params[:type] == 'home_cooked' ? 0 : d.currency,
                            :image_sd => d.image_sd,
                            :image_hd => d.image_hd,
                            :favourite => favourite,
                            :network => params[:type] == 'home_cooked' ? {} : {
                              :id => params[:type] == 'delivery' ? d.delivery_id : network_data.id,
                              :name => params[:type] == 'delivery' ? d.delivery.name : network_data.name
                            },
                            :type => params[:type] ||= nil
                          })
                        else
                          break
                        end
                      end
                      start = 1 if dish && d.id == dish.id
                    end
                  end
                end
            end
          end
    
          if dishes_array.count < limit && params[:type] != 'home_cooked'
            if params[:type] == 'delivery'
        
              if dishes_between = dishes.where("rating = 0")
                dishes_between.each do |d|
            
                  if dishes_array.count < limit
                    favourite = Favourite.find_by_user_id_and_dish_id(current_user_id, d.id) ? 1 : 0
                
                    dishes_array.push({
                      :id => d.id,
                      :name => d.name,
                      :rating => d.rating,
                      :votes => d.votes,
                      :price => d.price,
                      :currency => d.currency,
                      :image_sd => d.image_sd,
                      :image_hd => d.image_hd,
                      :favourite => favourite,
                      :network => {
                        :id => d.delivery_id,
                        :name => d.delivery.name
                      },
                      :type => params[:type] ||= nil
                    })
                  else
                    break
                  end
            
                end
              end
            else
        
              foursquare_max = Dish.select("max(fsq_checkins_count) as max_fsq").first.max_fsq
              fsq_checkins_count = foursquare_max if fsq_checkins_count.nil? || fsq_checkins_count == 0

              step_fsq = foursquare_max/2
              (0..(foursquare_max-step_fsq)).step(step_fsq) do |n|
      
                n1 = foursquare_max - n
                n2 = n1 - step_fsq != 0 ? n1 - step_fsq : 0
  
                if (fsq_checkins_count > n2 && fsq_checkins_count <= n1) || (fsq_checkins_count > n2 && fsq_checkins_count > n1 && dishes_array.count < limit)
    
                  start = 1 if fsq_checkins_count > n2 && fsq_checkins_count > n1 && dishes_array.count < limit
                  if dishes_between = dishes.where("fsq_checkins_count > ? AND fsq_checkins_count <= ? AND rating = 0", n2, n1)
      
                    dishes_between.each do |d|
                      if start == 1
                        if dishes_array.count < limit
                          network_data = Network.select([:id, :name]).find_by_id(d.network_id) 
                          if current_user_id > 0
                            favourite = Favourite.find_by_user_id_and_dish_id(current_user_id, d.id) ? 1 : 0
                          end
                          dishes_array.push({
                            :id => d.id,
                            :name => d.name,
                            :rating => d.rating,
                            :votes => d.votes,
                            :price => d.price,
                            :currency => d.currency,
                            :image_sd => d.image_sd,
                            :image_hd => d.image_hd,
                            :favourite => favourite,
                            :network => {
                              :id => network_data.id,
                              :name => network_data.name
                            },
                            :type => params[:type] ||= nil
                          })
                        else
                          break
                        end
                      end
                      start = 1 if dish && d.id == dish.id
                    end
                  end
                end
              end   
                 
            end
          end
    
          restaurants_array = []
          dishes_array.index_by {|r| r[:network][:id]}.values.each do |dish|
            Restaurant.select([:id, :name, :lat, :lon, :address, :network_id]).where(:network_id => dish[:network][:id]).by_distance(lat, lon).take(3).each do |r|
              restaurants_array.push({
                :id => r.id,
                :name => r.name,
                :lat => r.lat,
                :lon => r.lon,
                :address => r.address,
                :network_id => r.network_id,
              })
            end
          end
        end
      else
        $error = {:description => 'Parameters missing', :code => 8}    
      end
    end
    
    return render :json => {
            :dishes => dishes_array,
            :restaurants => restaurants_array,
            :error => $error
    }
  end
  
  def get_restaurants    
    
    limit = 25
    offset = params[:offset] ||= 0
    load_additional = 1
    
    if offset.to_i > 25
      return render :json => {
        :load_additional => load_additional ||= 0,
        :restaurants => [],
        :deliveries => [],
        :networks => [],
        :error => $error
      }
    end

    top_user_id = params[:top_user_id].to_i
    user_id = params[:user_id].to_i
    
    num_images = 20 
    favourite = 0  
    
    if top_user_id > 0
      
      networks = []
      delivery = Delivery.select('deliveries.photo, deliveries.fsq_id, deliveries.id, deliveries.name, deliveries.address, deliveries.city, deliveries.lat, deliveries.lon, deliveries.rating, deliveries.votes').where("top_user_id = ?",top_user_id).order('deliveries.updated_at DESC')
      
      delivery.each do |r|
        dishes = []    
        dishes_w_img = r.dish_deliveries.select('DISTINCT dish_deliveries.id, dish_deliveries.name, dish_deliveries.photo, dish_deliveries.rating, dish_deliveries.votes, dish_deliveries.dish_type_id').order("(dish_deliveries.rating - 3)*dish_deliveries.votes DESC, dish_deliveries.photo DESC").includes(:reviews).where("dish_deliveries.photo IS NOT NULL OR (dish_deliveries.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images)
    
        dishes_w_img.each do |dish|
          if user_id > 0
            favourite = Favourite.find_by_user_id_and_dish_id(user_id, dish.id) ? 1 : 0
          end
            dishes.push({
              :id => dish.id,
              :name => dish.name,
              :photo => dish.image_sd,
              :rating => dish.rating,
              :votes => dish.votes,
              :favourite => favourite
            })
        end
        networks.push({:network_id => r.id, :dishes => dishes, :type => 'delivery', :venues => r.fsq_id ? ["#{r.fsq_id}"] : []})
      end    
      
      restaurants = Restaurant.joins("LEFT OUTER JOIN `networks` ON `networks`.`id` = `restaurants`.`network_id` JOIN (
      #{Restaurant.select('id, address').where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL').order('restaurants.fsq_checkins_count DESC').to_sql}) r1
      ON `restaurants`.`id` = `r1`.`id`").where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL AND top_user_id = ?',top_user_id).order('restaurants.updated_at DESC').group('restaurants.name')

      restaurants.select('restaurants.id, restaurants.name, restaurants.address, restaurants.city, restaurants.lat, restaurants.lon, restaurants.rating, restaurants.votes, restaurants.network_id, restaurants.fsq_id')  

      restaurants.each do |r|
        dont_add = 0
        networks.each do |n|
          dont_add = 1 && break if r.network_id == n[:network_id]
        end
        if dont_add == 0
          dishes = []
          dishes_w_img = r.network.dishes.select('DISTINCT dishes.id, dishes.name, dishes.photo, dishes.rating, dishes.votes, dishes.dish_type_id').order("(dishes.rating - 3)*dishes.votes DESC, dishes.photo DESC").includes(:reviews).where("dishes.photo IS NOT NULL OR (dishes.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images)

          dishes_w_img.each do |dish|
            if user_id > 0
              favourite = Favourite.find_by_user_id_and_dish_id(user_id, dish.id) ? 1 : 0
            end
            dishes.push({
              :id => dish.id,
              :name => dish.name,
              :photo => dish.image_sd,
              :rating => dish.rating,
              :votes => dish.votes,
              :favourite => favourite
            })
          end
          networks.push({:network_id => r.network_id, :dishes => dishes, :type => nil, :venues => r.fsq_id ? ["#{r.fsq_id}"] : []}) 
        end
      end
      
    else  
      
      if params[:type] != 'delivery'
        xs = []
        filters = []
        if params[:bill] && params[:bill].length == 4 && params[:bill] != '0000' && params[:bill] != '1111'
          bill = []
          bill.push('bill = 1') if params[:bill][0] == '1'
          bill.push('bill = 2') if params[:bill][1] == '1'
          bill.push('bill = 3') if params[:bill][2] == '1'
          bill.push('bill = 4') if params[:bill][3] == '1'
          filters.push("(#{bill.join(' OR ')})") if bill.count > 0
        end
      
        etc = []
        etc.push('(wifi != 0 AND wifi != "нет" AND wifi != "NULL")') if params[:wifi] == '1'
        etc.push('terrace = 1') if params[:terrace] == '1'
        etc.push('cc = 1') if params[:accept_bank_cards] == '1'
        filters.push(etc.join(' AND ')) if etc.count > 0
        
        if params[:open_now].to_i == 1
          load_additional = 0
          wday = Date.today.strftime("%a").downcase
          now = Time.now.utc.strftime("%H%M")
          open_now = "#{now} + REPLACE(time_zone_offset, ':', '') BETWEEN REPLACE(LEFT(#{wday},5), ':', '') AND REPLACE(SUBSTRING(#{wday},7,11), ':', '')"
      
          if now.to_i < 1000
            now24 = now.to_i + 2400
            open_now = "(#{open_now} OR #{now24} BETWEEN REPLACE(LEFT(#{wday},5), ':', '') AND REPLACE(RIGHT(#{wday},7,11), ':', ''))"
          end
          
          open_now_id = "restaurants.id IN (#{WorkHour.select(:restaurant_id).where(open_now).collect {|r| r.restaurant_id}.join(',')})"
          filters.push(open_now_id)
          
        end  
        all_filters = filters.join(' AND ') if filters.count > 0
      end 
    
      city_radius = 30

      city_lat = 55.753548
      city_lon = 37.609239
      pi = Math::PI
    
      lat = !params[:lat].blank? ? params[:lat] : '55.753548'
      lon = !params[:lon].blank? ? params[:lon] : '37.609239'
    
      if params[:radius] == 'city'
        radius = 30
      else
        radius = params[:radius].to_f != 0 ? params[:radius].to_f : nil
      end
    
    
      if params[:type] == 'delivery'
        restaurants = Delivery.select('deliveries.photo, deliveries.fsq_id, deliveries.id, deliveries.name, deliveries.address, deliveries.city, deliveries.lat, deliveries.lon, deliveries.rating, deliveries.votes').where("top_user_id = ?",top_user_id).order("(rating - 3.5)*votes DESC")
      else
        if params[:sort] == 'distance'
          if radius
            restaurants = Restaurant.near(lat, lon, radius).by_distance(lat, lon)
          else
            restaurants = Restaurant.by_distance(lat, lon)
          end     
          restaurants = restaurants.joins('LEFT OUTER JOIN `networks` ON `networks`.`id` = `restaurants`.`network_id`').where('lat IS NOT NULL AND lon IS NOT NULL').order("restaurants.fsq_checkins_count DESC, networks.rating DESC, networks.votes DESC")
        elsif params[:sort] == 'popularity'
          if radius
            restaurants = Restaurant.near(lat, lon, radius)
          else
            restaurants = Restaurant
          end
          restaurants = restaurants.joins("LEFT OUTER JOIN `networks` ON `networks`.`id` = `restaurants`.`network_id` JOIN (
          #{Restaurant.select('id, address').where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL').order('restaurants.fsq_checkins_count DESC').to_sql}) r1
          ON `restaurants`.`id` = `r1`.`id`").where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL').order("restaurants.fsq_checkins_count DESC, (networks.rating - 3.5)*networks.votes DESC").by_distance(lat, lon).group('restaurants.name')
        else
         if radius
           restaurants = Restaurant.near(lat, lon, radius)
         else
           restaurants = Restaurant
         end
         restaurants = restaurants.joins("LEFT OUTER JOIN `networks` ON `networks`.`id` = `restaurants`.`network_id` JOIN (
         #{Restaurant.select('id, address').where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL').order('restaurants.fsq_checkins_count DESC').to_sql}) r1
         ON `restaurants`.`id` = `r1`.`id`").where('restaurants.lat IS NOT NULL AND restaurants.lon IS NOT NULL').order("(networks.rating - 3.5)*networks.votes DESC, restaurants.fsq_checkins_count DESC").by_distance(lat, lon).group('restaurants.name')
        end
      
      end
    
      unless params[:search].blank?
        search = params[:search].gsub(/[']/) { |x| '\\' + x }
        if params[:type] == 'delivery' 
          name = "deliveries.`name`"
          name_eng = "deliveries.`name_eng`"
          restaurants = restaurants.where("#{name} LIKE ? OR #{name_eng} LIKE ? ", "%#{search}%", "%#{search}%")
        else
          name = "restaurants.`name`"
          name_eng = "restaurants.`name_eng`"
          if rcs = RestaurantCategory.where('name LIKE ?', "%#{search}%")
            rc_ids = []
            rcs.each do |rc|
              rc_ids.push(",?[[:<:]]#{rc.id}[[:>:]],?")
            end
            if rc_ids.count > 0
              restaurants = restaurants.where("#{name} LIKE ? OR #{name_eng} LIKE ? OR restaurant_categories REGEXP ?", "%#{search}%", "%#{search}%", rc_ids.join('|'))
            else
              restaurants = restaurants.where("#{name} LIKE ? OR #{name_eng} LIKE ?", "%#{search}%", "%#{search}%")              
            end
          else
            restaurants = restaurants.where("#{name} LIKE ? OR #{name_eng} LIKE ? ", "%#{search}%", "%#{search}%")
          end
        end
        
      end
    
      restaurants = restaurants.search_by_word(params[:keyword]) unless params[:keyword].blank?
      restaurants = restaurants.search_by_tag_id(params[:tag_id]) if params[:tag_id].to_i > 0
      restaurants = restaurants.where(all_filters) unless all_filters.blank?
      restaurants = restaurants.where("network_id IN (#{params[:network_id]})") unless params[:network_id].blank?
      restaurants = restaurants.where(:active => true)
    
      if params[:type] != 'delivery'
        restaurants = restaurants.select('restaurants.ylp_rating, restaurants.ylp_reviews_count, restaurants.bill, restaurants.fsq_checkins_count, restaurant_categories, restaurants.id, restaurants.name, restaurants.address, restaurants.city, restaurants.lat, restaurants.lon, restaurants.rating, restaurants.votes, restaurants.network_id, restaurants.fsq_id')    
      end
      restaurants = restaurants.limit("#{offset}, #{limit}")
    
      networks = []
      if params[:type] == 'delivery'
      
        restaurants.each do |r|
          dishes = []
      
          if params[:tag_id].to_i > 0
            dishes_w_img = r.dish_deliveries.select('DISTINCT dish_deliveries.id, dish_deliveries.name, dish_deliveries.photo, dish_deliveries.rating, dish_deliveries.votes, dish_deliveries.dish_type_id').order("(dish_deliveries.rating - 3)*dish_deliveries.votes DESC, dish_deliveries.photo DESC").includes(:reviews).where("dish_deliveries.photo IS NOT NULL OR (dish_deliveries.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images).search_by_tag_id(params[:tag_id])
          else
            dishes_w_img = r.dish_deliveries.select('DISTINCT dish_deliveries.id, dish_deliveries.name, dish_deliveries.photo, dish_deliveries.rating, dish_deliveries.votes, dish_deliveries.dish_type_id').order("(dish_deliveries.rating - 3)*dish_deliveries.votes DESC, dish_deliveries.photo DESC").includes(:reviews).where("dish_deliveries.photo IS NOT NULL OR (dish_deliveries.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images)
          end
      
          dishes_w_img.each do |dish|
            if user_id > 0
              favourite = Favourite.find_by_user_id_and_dish_id(user_id, dish.id) ? 1 : 0
            end
            dishes.push({
              :id => dish.id,
              :name => dish.name,
              :photo => dish.image_p120,
              :rating => dish.rating,
              :votes => dish.votes,
              :favourite => favourite
            })
          end
          if user_id > 0
            favourite = Favourite.find_by_user_id_and_network_id(user_id, r.network_id) ? 1 : 0
          end
          networks.push(
            :network_id => params[:type] == 'delivery' ? '' : r.network_id,
            :favourite => favourite,
            :type => 'delivery',            
            :dishes => dishes,
            :venues => r.fsq_id ? ["#{r.fsq_id}"] : []
          )
        end
      else  
      
        restaurants.each do |r|
          dont_add = 0
          networks.each do |n|
            dont_add = 1 && break if r.network_id == n[:network_id]
          end
          if dont_add == 0
            dishes = []
        
            if params[:tag_id].to_i > 0
              dishes_w_img = r.network.dishes.select('DISTINCT dishes.id, dishes.name, dishes.photo, dishes.rating, dishes.votes, dishes.dish_type_id').order("(dishes.rating - 3)*dishes.votes DESC, dishes.photo DESC").includes(:reviews).where("dishes.photo IS NOT NULL OR (dishes.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images).search_by_tag_id(params[:tag_id])
            else
              dishes_w_img = r.network.dishes.select('DISTINCT dishes.id, dishes.name, dishes.photo, dishes.rating, dishes.votes, dishes.dish_type_id').order("(dishes.rating - 3)*dishes.votes DESC, dishes.photo DESC").includes(:reviews).where("dishes.photo IS NOT NULL OR (dishes.rating > 0 AND reviews.photo IS NOT NULL)").limit(num_images)
            end
        
            dishes_w_img.each do |dish|
              if user_id > 0
                favourite = Favourite.find_by_user_id_and_dish_id(user_id, dish.id) ? 1 : 0
              end
              dishes.push({
                :id => dish.id,
                :name => dish.name,
                :photo => dish.image_p120,
                :rating => dish.rating,
                :votes => dish.votes,
                :favourite => favourite
              })
            end
            
            fsq_id_arr = []
            r.network.restaurants.each do |fsq|
              fsq_id_arr.push(fsq.fsq_id) unless fsq.fsq_id.nil?
            end
            if user_id > 0
              favourite = Favourite.find_by_user_id_and_network_id(user_id, r.network_id) ? 1 : 0
            end
            networks.push(
              :network_id => r.network_id,
              :favourite => favourite,
              :type => nil,
              :dishes => dishes,
              :venues => fsq_id_arr ||= []
            )
          end
        end
      
      end
    end
    
    if restaurants.first.class.name == 'Delivery'
      delivery = restaurants
      restaurants = nil
    end
      
    return render :json => {
          :load_additional => load_additional ||= 0,
          :restaurants => restaurants ? restaurants.as_json({:keyword => params[:keyword] ||= nil}) : [],
          :deliveries => delivery ? delivery.as_json : [],
          :networks => networks,
          :error => $error
    }
    
  end
  
  def upload_photo
    if params[:uuid] && params[:photo]     
      $error = {:description => 'Fails to load image', :code => 9} unless Image.create({:photo => params[:photo], :uuid => params[:uuid]})           
    else
      $error = {:description => 'Parameters missing', :code => 8}
    end
    
    return render :json => {
      :error => $error
    }
  end
  
  def get_review  
    
    if params[:review_id]
      if params[:self_review].to_i == 1
        review = Dish.find_by_id(params[:review_id]).self_review
      else
        review = Review.find_by_id(params[:review_id])
      end
    else
      $error = {:description => 'Parameters missing', :code => 8}
    end
    
    review = review.format_review_for_api(params[:user_id]) if review && params[:info].to_i == 1
    return render :json => {
      :review => review,
      :error => $error
    }
  end
  
  def get_user_stats
    if user = User.find_by_id(params[:user_id])
      
      following_count = Follower.select(:id).where(:user_id => user.id).count(:id) rescue 0 
      followers_count = Follower.select(:id).where(:follow_user_id => user.id).count(:id) rescue 0
            
      if likes_a = Review.select([:id, :photo, :dish_id, :rtype]).where('id IN (SELECT review_id FROM likes WHERE user_id = ?)', user.id).order('id DESC')
        likes = {:data => [], :count => 0}        
        
        likes_a.each do |l|
          favourite = Favourite.find_by_user_id_and_dish_id(user.id, l.dish_id) ? 1 : 0
          
          case l.rtype
          when 'home_cooked'
            dish_name = l.home_cook.name
          when 'delivery'
            dish_name = l.dish_delivery.name
          else
            dish_name = l.dish ? l.dish.name : ''
          end
          
          likes[:data].push(
            :id => l.id,
            :dish_id => l.dish_id,
            :photo => l.photo.iphone.url == '/images/noimage.jpg' ? '' : l.photo.iphone.url,
            :name => dish_name ||= '',
            :favourite => favourite,
          )
        end
        likes[:count] = likes_a.count
      end
      
      if reviews_a = Review.select([:id, :photo, :dish_id, :rtype]).where('user_id = ?', user.id).order('id DESC')
        reviews = {:data => [], :count => 0}
        
        reviews_a.each do |r|
          favourite = Favourite.find_by_user_id_and_dish_id(user.id, r.dish_id) ? 1 : 0
         
          case r.rtype
          when 'home_cooked'
            dish_name = r.home_cook.name
          when 'delivery'
            dish_name = r.dish_delivery.name
          else
            dish_name = r.dish ? r.dish.name : ''
          end
          
          reviews[:data].push(
            :id => r.id,
            :dish_id => r.dish_id,
            :photo => r.photo.iphone.url == '/images/noimage.jpg' ? '' : r.photo.iphone.url,
            :name => dish_name ||= '',
            :favourite => favourite
          )
        end
        reviews[:count] = reviews_a.count
      end
      
      top_in_restaurants = {:data => [], :count => 0}
      if restaurants = Restaurant.select([:id, :name, :photo, :network_id]).where(:top_user_id => user.id).order('updated_at DESC')
        
        restaurants.each do |d|
          favourite = Favourite.find_by_user_id_and_network_id(user.id, d.network_id) ? 1 : 0
          top_in_restaurants[:data].push(
            :id => d.id,
            :name => d.name ? d.name : '',
            :photo => d.thumb,
            :favourite => favourite,
            :type => nil
          )
        end
      end
      
      if restaurants = Delivery.select([:id, :name, :photo]).where(:top_user_id => user.id).order('updated_at DESC')
        restaurants.each do |d|
          favourite = Favourite.find_by_user_id_and_delivery_id(user.id, d.id) ? 1 : 0
          top_in_restaurants[:data].push(
            :id => d.id,
            :name => d.name ? d.name : '',
            :photo => d.thumb,
            :favourite => favourite,
            :type => 'delivery'
          )
        end
      end
      top_in_restaurants[:count] = top_in_restaurants[:data].count
      
      top_in_dishes = {:data => [], :count => 0}
      
      if dishes = Dish.select([:id, :name, :photo, :created_at]).where(:top_user_id => user.id).order('id DESC')
        dishes.each do |d|
          favourite = Favourite.find_by_user_id_and_dish_id(user.id, d.id) ? 1 : 0
          top_in_dishes[:data].push(
            :id => d.id,
            :name => d.name ? d.name : '',
            :photo => d.image_sd,
            :type => nil,
            :favourite => favourite,
            :created_at => d.created_at
          )
        end
      end
      
      if dishes = DishDelivery.select([:id, :name, :photo, :created_at]).where(:top_user_id => user.id).order('id DESC')
        dishes.each do |d|
          favourite = Favourite.find_by_user_id_and_dish_delivery_id(user.id, d.id) ? 1 : 0
          top_in_dishes[:data].push(
            :id => d.id,
            :name => d.name ? d.name : '',
            :photo => d.image_sd,
            :type => 'delivery',
            :favourite => favourite,
            :created_at => d.created_at
          )
        end
      end
      
      if dishes = HomeCook.select([:id, :name, :photo, :created_at]).where(:top_user_id => user.id).order('id DESC')
        dishes.each do |d|
          favourite = Favourite.find_by_user_id_and_home_cook_id(user.id, d.id) ? 1 : 0
          top_in_dishes[:data].push(
            :id => d.id,
            :name => d.name ? d.name : '',
            :photo => d.image_sd,
            :type => 'home_cooked',
            :favourite => favourite,
            :created_at => d.created_at
          )
        end
      end
      top_in_dishes[:count] = top_in_dishes[:data].count
      top_in_dishes[:data] = top_in_dishes[:data].sort_by { |k| k[:created_at] }.reverse
      
      favourite_dishes = {:data => [], :count => 0}
      favourite_restaurants = {:data => [], :count => 0}
      if favourite = Favourite.where(:user_id => user.id)
        favourite.each do |f|
          
          if !f.restaurant_id.blank?
            if d = Restaurant.select([:id, :name, :photo, :network_id]).find_by_id(f.restaurant_id)
              favourite_restaurants[:data].push(
                :id => d.id,
                :name => d.name ? d.name : '',
                :photo => d.thumb,
                :favourite => 1,
                :type => nil
              )
            end
          elsif !f.delivery_id.blank?
            if d = Delivery.select([:id, :name, :photo]).find_by_id(f.delivery_id)
              favourite_restaurants[:data].push(
                :id => d.id,
                :name => d.name ? d.name : '',
                :photo => d.thumb,
                :favourite => 1,
                :type => 'delivery'
              )
            end
          elsif !f.dish_id.blank?
            if d = Dish.select([:id, :name, :photo, :created_at]).find_by_id(f.dish_id)
              favourite_dishes[:data].push(
                :id => d.id,
                :name => d.name ? d.name : '',
                :photo => d.image_sd,
                :type => nil,
                :favourite => 1,
                :created_at => d.created_at
              )
            end
          elsif !f.dish_delivery_id.blank?
            if d = DishDelivery.select([:id, :name, :photo, :created_at]).find_by_id(f.dish_delivery_id)
              favourite_dishes[:data].push(
                :id => d.id,
                :name => d.name ? d.name : '',
                :photo => d.image_sd,
                :type => 'delivery',
                :favourite => favourite,
                :created_at => d.created_at
              )
            end
          elsif !f.home_cook_id.blank?
            if d = HomeCook.select([:id, :name, :photo, :created_at]).find_by_id(f.home_cook_id)
              favourite_dishes[:data].push(
                :id => d.id,
                :name => d.name ? d.name : '',
                :photo => d.image_sd,
                :type => 'home_cooked',
                :favourite => 1,
                :created_at => d.created_at
              )
            end
          end
          
        end
      end
      # favourite_dishes[:count] = favourite_dishes[:data].count
      # favourite_dishes[:data] = favourite_dishes[:data].sort_by { |k| k[:created_at] }.reverse
      # 
      # favourite_restaurants[:count] = favourite_restaurants[:data].count
      # favourite_restaurants[:data] = favourite_restaurants[:data].sort_by { |k| k[:created_at] }.reverse
      
      return render :json => {
            # :favourite_dishes => favourite_dishes,
            # :favourite_restaurants => favourite_restaurants,
            :likes => likes,
            :dish_ins => reviews,
            :top_in_dishes => top_in_dishes,
            :top_in_restaurants => top_in_restaurants,
            :following_count => following_count,
            :followers_count => followers_count,
            :photo => user.user_photo,
            :error => $error
      }
    else
      $error = {:description => 'Parameters missing', :code => 941}
      return render :json => {
            :error => $error
      }
    end
  end
  
  def get_notifications
    if Session.check_token(params[:user_id], params[:token])
      
      limit = params[:limit] ? params[:limit] : 100
      offset = params[:offset] ? params[:offset] : 0
      
      data = []
      APN::Notification.where("user_id_to = ?", params[:user_id]).group('review_id, user_id_to, notification_type, user_id_from').limit(limit).order("id DESC").each do |n|
        user = User.find_by_id(n.user_id_from)
        data.push({
          :date => n.created_at.to_i,
          :type => n.notification_type,
          :review_id => n.review_id,
          :read => n.read,
          :text => n.alert,
          :user => {
            :name => user ? user.name : '',
            :id => user ? user.id : '',
            :photo => user ? user.user_photo : ''
          }
        })
      end
      APN::Notification.where("user_id_to = ?", params[:user_id]).limit(limit).order("id DESC").each { |n| n.update_attributes(:read => 1)}
      
      return render :json => {
            :notifications => data,
            :error => $error
      }    
    else
      return render :json => {
            :error => {:description => 'Parameters missing', :code => 1169}
      }
    end
  end
  
  def get_reviews
    limit = params[:limit] ? params[:limit] : 25
    
    if params[:following_for_user_id].to_i > 0
      reviews = Review.following(params[:following_for_user_id].to_i)
    elsif params[:liked_reviews_for_user_id]
      reviews = Review.where('id IN (SELECT review_id FROM likes WHERE user_id = ?)', params[:liked_reviews_for_user_id])
    elsif params[:reviews_for_user_id]
      reviews = Review.where('user_id = ?',params[:reviews_for_user_id])
    else
      if params[:lat] && params[:lon] 
        lat = params[:lat].to_f.round(2)
        lng = params[:lon].to_f.round(2)
      else 
        lat = 40.77
        lng = -73.98
      end      
      reviews = Review.where('photo IS NOT NULL').near(lat,lng)
    end
    
    reviews = reviews.limit(limit).order('id DESC').includes(:dish)
    reviews = reviews.where("id < ?", params[:review_id]) if params[:review_id]
    
    review_data = []
    reviews.each {|rw| review_data.push(rw.format_review_for_api(params[:user_id]))}    
    
    if !params[:user_id].blank?    
      if n = APN::Notification.where(:user_id_to => params[:user_id], :read => 0).last  
        n_count = n.badge
      end
    end
    
    return render :json => {
      :notifications => n_count ||= 0,
      :reviews => review_data,
      :error => $error
    }
          
  end
  
  def like_review
    
    if params[:review_id] && Session.check_token(params[:user_id], params[:token])
      data = Like.save(params[:user_id], params[:review_id], params[:self_review])
    else
      $error = {:description => 'Parameters missing', :code => 8}
    end
    
    return render :json => {
      :error => $error
    }
  end
  
  def comment_on_review
    if params[:comment] && params[:review_id] && Session.check_token(params[:user_id], params[:token])
      comment_id = Comment.add({:user_id => params[:user_id], :review_id => params[:review_id], :text => params[:comment]}, params[:self_review])
      return render :json => {
        :error => $error,
        :comment_id => comment_id
      }
    else
      return render :json => {
        :error => {:description => 'Parameters missing', :code => 1330}
      }
    end
  end
  
  def get_restaurant_menu
    if params[:restaurant_id]
      user_id = params[:user_id].to_i
      
      if params[:type] == 'delivery'
        if restaurant = Delivery.find_by_id(params[:restaurant_id])
          dishes = DishDelivery.where('delivery_id = ?', restaurant.id)
        else
          $error = {:description => 'Restaurant not found', :code => 357}
        end
      else
        if restaurant = Restaurant.find_by_id(params[:restaurant_id])
          dishes = Dish.where('network_id = ?', restaurant.network_id)
        else
          $error = {:description => 'Restaurant not found', :code => 357}
        end
      end
      
      if dishes.count > 0
      
        categories = []
        types = []
      
        dishes.select(:dish_category_id).group(:dish_category_id).each do |dish|
          sort = DishCategoryOrder.find_by_network_id_and_dish_category_id(restaurant.network_id, dish.dish_category_id) if params[:type] != 'delivery'
          categories.push({
            :id => dish.dish_category_id, 
            :name => dish.dish_category.name_eng.nil? ? dish.dish_category.name : dish.dish_category.name_eng, 
            :order => sort ? sort.order : 9999
          })
        end
        categories = categories.sort_by{|k| k[:order] && k.delete(:order) }
      
        dishes.select(:dish_type_id).group(:dish_type_id).each do |dish|
          types.push({:id => dish.dish_type.id, :name => dish.dish_type.name_eng, :order => dish.dish_type.order}) if dish.dish_type
        end

        types = types.sort_by{|k| k[:order] }        
        
        dishes_f = []
        favourite = 0
        
        dishes.select([:id, :name, :dish_category_id, :dish_type_id, :description, :rating, :votes, :photo, :price, :currency]).each do |d|
          if user_id > 0
            if params[:type] == 'delivery'  
              favourite = Favourite.find_by_user_id_and_dish_delivery_id(user_id, d.id) ? 1 : 0
            else
              favourite = Favourite.find_by_user_id_and_dish_id(user_id, d.id) ? 1 : 0
            end
          end
          dishes_f.push(
            :dish => { 
              :id => d.id, 
              :name => d.name, 
              :dish_category_id => d.dish_category_id, 
              :dish_type_id => d.dish_type_id, 
              :description => d.description, 
              :rating => d.rating, 
              :votes => d.votes,
              :image_sd => d.image_sd, 
              :image_hd => d.image_hd, 
              :price => d.price,
              :currency => d.currency ||= '',
              :favourite => favourite
          })
        end
             
        return render :json => {
          :dishes => dishes_f, 
          :categories => categories.as_json(),
          :types => types.as_json,
          :error => $error
        }        
      end
    else
      $error = {:description => 'Parameters missing', :code => 8}
    end
    return render :json => {
      :error => $error
    }
  end
  
  def add_review
    if params[:review] && Session.check_token(params[:review][:user_id], params[:token]) && params[:review][:rating].to_f > 0 && params[:review][:rating].to_f <= 5
      
      if User.find_by_id(params[:review][:user_id])
        params[:review][:friends] = User.put_friends(params[:fb_friends], params[:tw_friends]) if params[:fb_friends] || params[:tw_friends]
        params[:review][:photo] ||= params[:uuid] #Delete on release
      
        if params[:review][:rtype] == 'home_cooked'
          
                if params[:dish] && params[:dish][:name] && params[:dish][:dish_type_id]   
                  unless dish = HomeCook.find_by_name(params[:dish][:name])
            
                    unless dish = HomeCook.create(params[:dish])
                      return render :json => {:error => {:description => 'Dish create error', :code => 6}}
                    end

                  end
                  params[:review][:dish_id] = dish.id
                else
                  return render :json => {:error => {:description => 'Home Cooked is Missing', :code => 1015}}
                end
        
              r = Review.save_review(params[:review], params[:post_on_facebook], params[:post_on_twitter])
            
        elsif params[:review][:rtype] == 'delivery'
              
                if r = Delivery.find_by_id(params[:review][:restaurant_id])
                  params[:review][:restaurant_id] = r.id
                elsif params[:foursquare_venue_id]
                  if r = Delivery.add_from_4sq_with_menu(params[:foursquare_venue_id])        
                    params[:review][:restaurant_id] = r.id
                  end
                else
                  return render :json => {:error => {:description => 'Delivery not found', :code => 1}}
                end
        
                unless dish = DishDelivery.find_by_id(params[:review][:dish_id])
                  if params[:dish] && params[:dish][:name]
                    params[:dish][:delivery_id] = r.id  

                    unless dish = DishDelivery.create(params[:dish])
                      return render :json => {:error => {:description => 'DishDelivery create error', :code => 6}}
                    end

                  else
                    return render :json => {:error => {:description => 'DishDelivery find error', :code => 6}}
                  end
                end
        
                params[:review][:dish_id] = dish.id
                r = Review.save_review(params[:review], params[:post_on_facebook], params[:post_on_twitter])
      
        else
                if r = Restaurant.find_by_id(params[:review][:restaurant_id])
                  params[:review][:network_id] = r.network_id
                elsif r = Restaurant.add_from_4sq_with_menu(params[:foursquare_venue_id])        
                  params[:review][:restaurant_id] = r.id
                  params[:review][:network_id] = r.network_id
                else
                  return render :json => {:error => {:description => 'Restaurant not found', :code => 1}}
                end
        
                unless dish = Dish.find_by_id(params[:review][:dish_id])
                  if params[:dish] && params[:dish][:name]  

                    params[:dish][:network_id] = r.network_id
                    params[:dish][:created_by_user] = params[:review][:user_id]

                    unless dish = Dish.create(params[:dish])
                      return render :json => {:error => {:description => 'Dish create error', :code => 6}}
                    end
            
                  else
                    return render :json => {:error => {:description => 'Dish find error', :code => 6}}
                  end
                end
        
                params[:review][:dish_id] = dish.id
                r = Review.save_review(params[:review], params[:post_on_facebook], params[:post_on_twitter])
        end   
      else
        $error = {:description => 'User not found', :code => 1515}  
      end
    else
      $error = {:description => 'We\'re sorry, but we have some problems with your review, try to login/logout and post again', :code => 1515}  
    end
    
    return render :json => {
      :dish_id => params[:review][:dish_id],
      :restaurant_id => params[:review][:restaurant_id],
      :review_id => r.id,
      :error => $error
    }
  
  end
  
end