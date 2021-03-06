class Follower < ActiveRecord::Base
  validates :user_id, :uniqueness => {:scope => :follow_user_id}
  
  def destroy
    if n = APN::Notification.find_by_user_id_from_and_user_id_to_and_notification_type(user_id,follow_user_id,'following')
      n.destroy
    end
    super
  end
  
  def self.create(data)    
    follow = super(data)
    system "rake facebook:follow ID='#{follow.id}' &"
  end
  
end
