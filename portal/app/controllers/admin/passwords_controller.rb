# frozen_string_literal: true

module Admin
  # Change your own password (forced on first sign-in).
  class PasswordsController < BaseController
    def edit; end

    def update
      unless current_admin.authenticate(params[:current_password].to_s)
        return redirect_to(edit_admin_password_path, alert: 'Your current password is not correct.')
      end
      if params[:password] == params[:current_password]
        return redirect_to(edit_admin_password_path, alert: 'Choose a password different from the current one.')
      end

      if current_admin.update(password: params[:password], password_confirmation: params[:password_confirmation],
                              must_change_password: false)
        current_admin.sessions.where.not(id: Current.session.id).delete_all
        audit('password_changed')
        redirect_to admin_root_path, notice: 'Password changed.'
      else
        redirect_to edit_admin_password_path, alert: current_admin.errors.full_messages.to_sentence
      end
    end
  end
end
