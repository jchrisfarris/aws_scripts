#!/usr/bin/ruby

# This script is useful if you're on the road and need to permit yourself access to your instance

require 'aws-sdk-resources'
require 'optparse'
require 'csv'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
  opts.on("-o", "--object s3object", "process this s3 url") do |s3object|
    options[:s3object] = s3object
  end
  opts.on("-b", "--bucket bucket", "process this s3 url") do |bucket|
    options[:bucket] = bucket
  end
  opts.on("-f", "--file file", "Process this file") do |file|
    options[:file] = file
  end

  opts.on("-p", "--product", "Show output by product") do |p|
    options[:product] = p
  end
  opts.on("-s", "--service", "Show output by service") do |s|
    options[:service] = s
  end
  opts.on("-t", "--tag", "Show output by tag") do |t|
    options[:tag] = t
  end

end.parse!

if ENV['AWS_SECRET_ACCESS_KEY'] == ""
	puts "Your Keys are not in the environment. Failing to do anything"
	exit
end

# Lets pull the object if necessary. 
if options[:s3object] 
	puts "Getting #{options[:s3object]} from #{options[:bucket]} "
	s3 = Aws::S3::Resource.new()
	s3.bucket(options[:bucket]).object(options[:s3object]).get({response_target: "/tmp/#{options[:s3object]}" })
	options[:file] = "/tmp/#{options[:s3object]}"
end

file_to_process=options[:file]



# Amazon "conviently" add some disclaimers to make this not a try csv file. Bah. 
`grep ^\\\" #{file_to_process} > #{file_to_process}.valid`


# exit

# <CSV::Row "InvoiceID":"Estimated" "PayerAccountId":"37915xxxxx" "LinkedAccountId":"3791535xxxxx" "RecordType":"PayerLineItem" 
# "RecordID":"5400000000291679920-3" "BillingPeriodStartDate":"2015/11/01 00:00:00" "BillingPeriodEndDate":"2015/11/30 23:59:59" 
# "InvoiceDate":"2015/11/21 21:29:56" "PayerAccountName":"Chris Farris" "LinkedAccountName":"" "TaxationAddress":"Your Address" 
# "PayerPONumber":nil "ProductCode":"AWSDataTransfer" "ProductName":"AWS Data Transfer" 
# "SellerOfRecord":"Amazon Web Services, Inc." "UsageType":"USE1-APN1-AWS-In-Bytes" "Operation":nil "AvailabilityZone":"" 
# "RateId":"3510828" "ItemDescription":"$0.00 per GB - US East (Northern Virginia) data transfer from Asia Pacific (Tokyo)" 
# "UsageStartDate":"2015/11/01 00:00:00" "UsageEndDate":"2015/11/30 23:59:59" "UsageQuantity":"0.00015827" "BlendedRate":nil 
# "CurrencyCode":"USD" "CostBeforeTax":"0.000000" "Credits":"0.000000" "TaxAmount":"0.000000" "TaxType":"None" "TotalCost":"0.000000" 
# "aws:cloudformation:stack-name":"" "user:Name":"" "user:cost-allocation":"">

# Important Keys:
# 	InvoiceDate
# 	ProductCode
# 	UsageType
# 	ItemDescription
# 	UsageQuantity
# 	TotalCost
# 	user:cost-allocation

# We will track our credits as a single entity
credits = 0.0

# This is the sum-to-date
total_bill = 0.0

by_service = Hash.new
by_tag = Hash.new
by_product=Hash.new 

billing_data = CSV.foreach("#{file_to_process}.valid", headers: true) do |row|
	# puts row.inspect

	next if row["RecordType"] != "PayerLineItem"
	if row["TotalCost"].to_f < 0.0 
		# puts "CREDIT #{row["ProductCode"]} #{row["UsageType"]} #{row["UsageQuantity"]} #{row["TotalCost"]}"
		credits = credits + row["TotalCost"].to_f
	else
		# puts "COST #{row["ProductCode"]} #{row["UsageType"]} #{row["UsageQuantity"]} #{row["TotalCost"]}"

		service_key=row["ProductCode"] + "-" + row["UsageType"]
		# puts "\t #{service_key}"
		by_service[service_key] = by_service[service_key].to_f + row["TotalCost"].to_f

		by_product[row["ProductCode"]] = by_product[row["ProductCode"]].to_f + row["TotalCost"].to_f

		if row["user:cost-allocation"] == ""
			row["user:cost-allocation"] = "UNALLOCATED"
		end
		by_tag[row["user:cost-allocation"]] = by_tag[row["user:cost-allocation"]].to_f + row["TotalCost"].to_f

		total_bill = total_bill + row["TotalCost"].to_f
	end
	
end

if options[:product]
	puts "Bill by Product"
	sorted_array = by_product.sort_by{|_key, value| value}.reverse
	sorted_hash = Hash[*sorted_array.flatten]

	sorted_hash.keys.each do |k|
		if sorted_hash[k] > 0.0
			printf("\t%50s %f\n", k, sorted_hash[k])
		end
		# puts "\t#{k}\t\t#{by_service[k]}"
	end
end

if options[:service]
	puts "Bill By Service:"
	sorted_array = by_service.sort_by{|_key, value| value}.reverse
	sorted_hash = Hash[*sorted_array.flatten]

	sorted_hash.keys.each do |k|
		if sorted_hash[k] > 0.0
			printf("\t%50s %f\n", k, sorted_hash[k])
		end
		# puts "\t#{k}\t\t#{by_service[k]}"
	end
	# puts by_service.inspect
end



if options[:tag]
	puts "Bill By Tag:"
	sorted_array = by_tag.sort_by{|_key, value| value}.reverse
	sorted_hash = Hash[*sorted_array.flatten]

	sorted_hash.keys.each do |k|
		if sorted_hash[k] > 0.0
			printf("\t%20s %f\n", k, sorted_hash[k])
		end
		# puts "\t#{k}\t\t#{by_service[k]}"
	end
	# puts by_service.inspect
end


puts
puts "This bill has a total credit of #{credits}"
puts "This bill has a total cost of #{total_bill}"










