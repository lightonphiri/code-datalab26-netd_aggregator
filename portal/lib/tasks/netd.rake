namespace :netd do
  desc 'List problem reports (newest first). LIMIT=20'
  task reports: :environment do
    ProblemReport.order(created_at: :desc).limit(ENV.fetch('LIMIT', 20).to_i).each do |r|
      puts "##{r.id} #{r.created_at.strftime('%B %-d, %Y %H:%M')} | #{r.problem} | #{r.name} <#{r.email}> | emailed=#{r.emailed}"
      puts "   #{r.record_url}\n   #{r.message.to_s.tr("\n", ' ').truncate(300)}"
    end
  end
end
