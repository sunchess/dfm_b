desc "Delete dublicates in cuisines"
task :del_dbl_cus => :environment do
  RestaurantCuisine.group('restaurant_id, cuisine_id').having('count(*) > 1').each do |rc|
    RestaurantCuisine.delete_all("restaurant_id = #{rc.restaurant_id} AND cuisine_id = #{rc.cuisine_id}")
    p RestaurantCuisine.create(:restaurant_id => rc.restaurant_id, :cuisine_id => rc.cuisine_id)
  end
end

desc "Find Reviews with unexisted restaurant_id and fix it by find first restaurant in Review Network"
task :rev_rest_fix => :environment do
  Review.select([:id, :network_id, :restaurant_id, :rating]).where("restaurant_id IS NOT NULL && network_id IS NOT NULL").each do |rw|
    unless r = Restaurant.select(:id).find_by_id(rw.restaurant_id)
      if r = Restaurant.select([:id, :name, :votes, :rating]).find_by_network_id(rw.network_id)
        rw.restaurant_id = r.id
        rw.save
        
        reviews = Review.where(:restaurant_id => r.id)
        r.votes = reviews.count
        r.rating = reviews.sum(:rating)/reviews.count
        r.save
        p "#{rw.id}: #{r.id} #{r.name} #{r.votes}/#{r.rating}"
      else
        p "#{rw.id}: No restaurants found in Network #{rw.network_id}"
      end
    end
  end
end

desc "Recount count_likes for Reviews"
task :likes_up => :environment do
  Review.update_all({:count_likes => 0})
  Review.all.each do |r|
    r.count_likes = r.likes.count
    r.save
    p "#{r.id} #{r.count_likes}"
  end
end

desc "Create preferences for Users"
task :cr_user_refs => :environment do
  User.all.each do |u|
    p u.id if UserPreference.create(:user_id => u.id)
  end
end