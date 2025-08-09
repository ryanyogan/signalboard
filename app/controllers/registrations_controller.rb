class RegistrationsController < ApplicationController
  def new
    @user = User.new
  end

  private

    def user_params
      params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
    end

    def start_new_session_for(user)
      s = user.sessions.create!
      cookies.signed.permanent[:session_token] = {}
    end
end
