# DeployThing #
**DeployThing** is a convention-over-configuration method for simple deployment of applications into AWS auto-scaling groups. It's based on the [twelve-factor application](TODO) concept popularized by Heroku and, here at [Leaf](https://leaf.me), DeployThing has proven to be an effective building block for managing applications and application releases in a generic way.

DeployThing is built on the core idea that an application deployable _D_ is composed of artifact version _A_ and configuration version _C_, welded together in an immutable manner. (The shorthand, practically enough, is `A + C = D`.)

## Glossary ##

- An **application** is a class of artifact. It essentially provides a namespace for configuration, artifact, and deploys.
- An **artifact** is one instance of an application, as built by something like Jenkins. At Leaf, our artifacts are Docker containers tagged with the same name as a Git tag.
- A **policy** is an IAM policy document. DeployThing will create the appropriate IAM role or user (as requested; users with keys are easier in a Docker world) and attach this policy if the role does not exist; it will remove the role when the last launch (see below) using that role is taken down. (Users with keys are easier to manage in a Docker world.)
- A **configuration** is modeled as a set of files that should, by the instances being booted by `deploy_thing`, be made available to the application. Configurations are immutable, and any change to a configuration increments its configuration version number. At Leaf, we download these files and volume them into Docker containers.
- A **deployable** is a pairing of an artifact version and a configuration version. This, too, is immutable, _except for_ the exact user credentials passed in by DeployThing as part of the configuration version (i.e., the user was deleted when the last launch went away and needed to be recreated; it is semantically immutable).
- A **launch** is an auto-scaling group to which a deployable is (surprise!) deployed. `deploy_thing` will create a load balancer if it doesn't exist for this application and point it at this launch, which can then be re-pointed as appropriate when additional launches are performed.

## How It Works ##
DeployThing is particular about the parts of the deploy pipeline that it controls, but it's fairly straightforward in its behavior.

- Configurations are immutable within DeployThing. Any change to any file within the configuration system creates a new configuration numbered in ascending order.
- DeployThing will create auto-scaling groups on which your application can run, but is agnostic on the method of deployment; its only input to the auto-scaling groups is a specified user-data file into which _D_ will be injected. At Leaf, we use Chef to prep a Docker singleton environment, pull application container _A_, and launch that container with the files of _C_. Your methodology is probably different, and that's cool--DeployThing doesn't care.
- Artifact versions are not handled in the scope of DeployThing. The numbering and naming scheme of these artifacts is up to you; DeployThing only asks for a string.

## Installation ##

DeployThing is designed primarily for use as a command-line tool, though it's written with sufficient separation of concerns that it could be easily consumed as a library. DeployThing is available in [RubyGems](TODO) via ye olde `gem`:

```bash
gem install deploy_thing
```

### An Example Workflow ###
_(note: this is outdated at this point, but I haven't needed DeployThing for a new project enough to exhaustively update the docs. Shoot me an email if you're using this, it'll help me get back on the project.)_

1. Application `foo` is registered with `deploy_thing app new --name foo`.
2. You upload a DeployThing config file (as opposed to an application config file, which uses the same mechanism; `deploy_thing.yaml` is a reserved name) with `deploy_thing config upload --app foo --file /path/to/some_file.yaml --remote-file deploy_thing.yaml`. This creates config version `1` (the _C_ above). (Note that `--remote-file` is optional and will default to the local file name.)
3. Belatedly, you realize you typoed something, and use `deploy_thing config edit foo --remote-file deploy_thing.yaml` to open it in `vim` and edit it. The new version is 2.
4. Outside of DeployThing, Jenkins creates a Docker container with build number `1000`. (This is _A_, above.)
5. You specify an AWS policy that describes the AWS-facing capabilities of the application running this with `deploy_thing policy edit --application`; it opens `vim`, you make your edits, and you save. This creates policy `1`.
6. You launch your first deploy with `deploy_thing launch up --application foo --config 2 --policy 1 --artifact 1000`. (`--config` and `--policy` are optional and will default to the newest config available.) This will create a new deploy with version `1` and launch it into an auto-scaling group, with its particulars defined by `deploy_thing.yaml`. It will also create a load balancer off of the `deploy_thing.yaml` parameters and point it at the group and return the launch number of `001`.
7. Jenkins later spits out a new artifact, `1001`.
8. You launch your new deploy with `deploy_thing launch up --application foo --artifact 1001`, giving you launch `002`.
9. You switch over the load balancer to `002` with `deploy_thing lb switch --application foo --launch 002`.
10. You clean up launch `001` with `deploy_thing launch down --application foo --launch 001`.
11. You go get a tasty beverage. (Required. It's in the license. If you practice continuous delivery, I strongly advise non-diuretics.)

## Notes, Traps, Gotchas ##
- S3 is eventually consistent. Multiple users modifying the same application at the same time may produce wrong behavior and may lead to data loss. If you need multiple deployers, put this behind a web application or something.

## Contributing ##

1. Fork it ( https://github.com/eropple/deploy_thing/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
