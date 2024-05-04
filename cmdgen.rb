pwd=`echo $PWD`.chomp
uid=`id -u`.chomp
gid=`id -g`.chomp

basecmd="docker run"
flags="--rm -ti"
curdir=%{-v #{pwd}:#{pwd} --workdir=#{pwd}}
userspec="-u #{uid}:#{gid}"

imagename=ARGV[0]
version="latest"

puts "# version: #{ENV["VERSION"]}"

if !ENV["VERSION"].nil?
  version=ENV["VERSION"]

elsif File.exist?(".#{imagename}.version")
  version="#{File.read(".#{imagename}.version").chomp}"
end

image = "#{imagename}:#{version}"

envvar_arr=[
  %{XDG_CACHE_HOME="#{pwd}/.cache/#{imagename}.#{version}"},
  %{XDG_DATA_HOME="#{pwd}/.data/#{imagename}.#{version}"},
  %{XDG_STATE_HOME="#{pwd}/.state/#{imagename}.#{version}"},
  %{XDG_RUNTIME_DIR_HOME="#{pwd}/.runtime/#{imagename}.#{version}"},
  %{PYTHONUSERBASE="#{pwd}/.pip/#{imagename}.#{version}"},
  %{BUNDLE_PATH="#{pwd}/.bundler"},
  'BUNDLE_DISABLE_SHARED_GEMS=true',
  "HOME=#{pwd}"
]

envvars = envvar_arr.map {|x| "-e #{x}" }.join(' ')

ports=[]

if !ENV["EXPOSE"].nil?
  ports += ENV["EXPOSE"].split(",")

elsif File.exist?(".#{ARGV[0]}.ports")
  ports += File.read(".#{ARGV[0]}.ports").split("\n").to_a

end

portstring = ports.map{|x| "-p #{x}"}.join(',')

cmd2=ARGV[1]

ccmd=%{#{cmd2} #{ARGV[2..-1].join(' ')}}

arr = [
  basecmd,
  flags,
  curdir,
  userspec,
  envvars,
  portstring,
  image,
  ccmd
]

result = arr.join(' ')

print result
