# frozen_string_literal: true

# Admin panel accounts (SRS FR-36). Run on the server with deploy/ops/netd-user.sh, e.g.
#   netd-user.sh add EMAIL="jane@unza.zm" NAME="Jane Banda"   -> prints a one-time password (changed at first sign-in)
#   netd-user.sh add EMAIL=... NAME=... ROLE=viewer          -> read-only: ETD reports, metadata quality, usage
#   netd-user.sh role EMAIL=... ROLE=admin|viewer
#   netd-user.sh reset EMAIL=...     netd-user.sh disable EMAIL=...     netd-user.sh enable EMAIL=...     netd-user.sh list
namespace :netd do
  namespace :user do
    def one_time_password = SecureRandom.alphanumeric(16)

    def find_user!
      User.find_by!(email_address: ENV.fetch('EMAIL').strip.downcase)
    end

    desc 'Add an account: EMAIL=... NAME=... [ROLE=admin|viewer] (default admin)'
    task add: :environment do
      pw = one_time_password
      u = User.create!(email_address: ENV.fetch('EMAIL'), name: ENV.fetch('NAME'), password: pw, must_change_password: true,
                       role: ENV.fetch('ROLE', 'admin'))
      AdminEvent.record('user_added', u.email_address, "from the command line; role #{u.role}", user: nil)
      puts "added #{u.email_address} (#{u.role}); one-time password: #{pw}"
    end

    desc "Change an account's role and sign it out: EMAIL=... ROLE=admin|viewer"
    task role: :environment do
      u = find_user!
      u.update!(role: ENV.fetch('ROLE'))
      u.sessions.delete_all
      AdminEvent.record('user_role', u.email_address, "role #{u.role}", user: nil)
      puts "#{u.email_address} is now #{u.role}"
    end

    desc 'Give an account a new one-time password and sign it out everywhere: EMAIL=...'
    task reset: :environment do
      u = find_user!
      pw = one_time_password
      u.update!(password: pw, must_change_password: true)
      u.sessions.delete_all
      AdminEvent.record('password_reset', u.email_address, 'from the command line', user: nil)
      puts "reset #{u.email_address}; one-time password: #{pw}"
    end

    desc 'Disable an account and sign it out: EMAIL=...'
    task disable: :environment do
      u = find_user!
      u.update!(active: false)
      u.sessions.delete_all
      AdminEvent.record('user_disabled', u.email_address, 'from the command line', user: nil)
      puts "disabled #{u.email_address}"
    end

    desc 'Enable an account: EMAIL=...'
    task enable: :environment do
      u = find_user!
      u.update!(active: true)
      AdminEvent.record('user_enabled', u.email_address, 'from the command line', user: nil)
      puts "enabled #{u.email_address}"
    end

    desc 'List admin accounts'
    task list: :environment do
      User.order(:email_address).each do |u|
        puts format('%-40s %-28s %-7s %-8s last sign-in %s', u.email_address, u.name, u.role, u.active? ? 'active' : 'DISABLED',
                    u.last_sign_in_at&.utc&.strftime('%Y-%m-%d %H:%M UTC') || 'never')
      end
    end
  end
end
