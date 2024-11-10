pwd=`echo $PWD`.chomp
uid=`id -u`.chomp
gid=`id -g`.chomp
username=`echo $USR`.chomp

# prevent return carriages from affecting the command line
def puts(str)
  print "#{str} #\n"
end

basecmd="docker run"
flags="--rm -ti"
curdir=%{-v #{pwd}:#{pwd} --workdir=#{pwd}}
userspec="-u #{uid}:#{gid}"

imagename=ARGV[0]
cleanname= "#{ENV["CLEANNAME"]}".length.zero? ? imagename : ENV["CLEANNAME"]

version = "latest"
if "#{ENV["VERSION"]}".length != 0
  version=ENV["VERSION"]

elsif File.exist?(".#{cleanname}.version")
  version="#{File.read(".#{cleanname}.version").chomp}"

elsif File.exist?(".#{cleanname}-version")
  version="#{File.read(".#{cleanname}-version").chomp}"
end


puts "# version: #{version}"

if File.exist?(".#{cleanname}.prepare")
  slug = `pwd`.chomp.gsub(/[^a-zA-Z0-9]+/, '-')
  oldversion = version
  version = "#{version}-prepared-#{slug}"

  puts "# prepare: #{version}"

  File.write(".prebuild-dockerfile", <<~CONTENT)
    FROM #{cleanname}:#{oldversion}

    COPY .#{cleanname}.prepare /prebuild.bash

    RUN chmod +x /prebuild.bash && /prebuild.bash
  CONTENT

  params = ""

  if ENV["NOCACHE"] == '1'
    params += "--no-cache"
  end

  puts "docker build . #{params} --progress=plain -f .prebuild-dockerfile -t #{cleanname}:#{version} &> .docker-build.log"
end

if "#{ENV["NETWORK"]}".length != 0
  network=ENV["NETWORK"]

elsif File.exist?(".#{cleanname}.network")
  network="#{File.read(".#{cleanname}.network").chomp}"
end

puts "# network: #{network}"

networkstring = ""
if network
  networkstring = "--network #{network}"
end

image = "#{imagename}:#{version}"
hostnamespec = "--hostname #{image.gsub(/[^A-Za-z0-9]+/, '-')}"

envvar_arr=[
  %{XDG_CACHE_HOME="#{pwd}/.cache/#{cleanname}.#{version}"},
  %{XDG_DATA_HOME="#{pwd}/.data/#{cleanname}.#{version}"},
  %{XDG_STATE_HOME="#{pwd}/.state/#{cleanname}.#{version}"},
  %{XDG_RUNTIME_DIR_HOME="#{pwd}/.runtime/#{cleanname}.#{version}"},
  %{PYTHONUSERBASE="#{pwd}/.pip/#{cleanname}.#{version}"},
  %{BUNDLE_PATH="#{pwd}/.bundler"},
  'BUNDLE_DISABLE_SHARED_GEMS=true',
  "HOME=#{pwd}"
]

if File.exist?(".#{cleanname}.env")
  lines = File.read(".#{cleanname}.env").split("\n")
  envvar_arr += lines
end

if File.exist?(".#{cleanname}.openv")
  lines = File.read(".#{cleanname}.openv").split("\n")
  lines.each do |line|
    t1 = line.split('=')
    envname = t1[0]
    t2 = t1[1].split(':')
    id = t2[0]
    field = t2[1]

    stuff = %Q{`op item get --reveal "#{id}" --fields label="#{field}"`}

    envvar_arr << %Q{#{envname}="#{stuff}"}
  end
end

envvars = envvar_arr.map {|x| "-e #{x}" }.join(' ')

ports=[]

if "#{ENV["EXPOSE"]}".length != 0
  ports += ENV["EXPOSE"].split(",")

elsif File.exist?(".#{ARGV[0]}.ports")
  ports += File.read(".#{ARGV[0]}.ports").split("\n").to_a
end

use_gpu = false
gpu_runtime = "nvidia"
gpu_choice = "all"

if "#{ENV["GPU_RUNTIME"]}".length != 0
  gpu_runtime = ENV["GPU_RUNTIME"]
  use_gpu = true

elsif File.exist?(".#{ARGV[0]}.gpu_runtime")
  gpu_runtime = File.read(".#{ARGV[0]}.gpu_runtime")
  use_gpu = true
end

if "#{ENV["GPU"]}".length != 0
  gpu_choice = ENV["GPU"]
  use_gpu = true

elsif File.exist?(".#{ARGV[0]}.gpu_choice")
  gpu_choice = File.read(".#{ARGV[0]}.gpu_choice")
  use_gpu = true

end

gpustring = ""

if use_gpu
  puts "# using gpu runtime #{gpu_runtime}"
  puts "# using gpu #{gpu_choice}"
  gpustring = "--runtime=#{gpu_runtime} --gpus #{gpu_choice}"
end

portstring = ports.map{|x| "-p #{x}"}.join(',')

cmd2=ARGV[1]

ccmd=%{#{cmd2} #{ARGV[2..-1]&.join(' ')}}

arr = [
  basecmd,
  flags,
  hostnamespec,
  curdir,
  userspec,
  envvars,
  portstring,
  gpustring,
  networkstring,
  image,
  ccmd
]

result = arr.join(' ')

print result
