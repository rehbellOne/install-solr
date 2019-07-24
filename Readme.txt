
Credit goes to Viet Hoang for the original script work: https://gitlab.com/viet.hoang/workshop/blob/master/Scripts%20for%20Sitecore%209.1/install-solr.ps1
Here's a link to his blog where I learned about his work: https://buoctrenmay.com/2018/11/29/sitecore-xp-9-1-step-by-step-install-guide-on-your-machine/

I've made quite a number of changes to the script to automate some more of the work. I feel that this was more toward my needs than what he had originally.

I needed side by side SOLR installs, and I wanted them all organized in a specific way. 
I also wanted the services created with specific conventions so that I could organize them in the host OS.

Set the SolutionPrefix, Version of SOLR, Website Host Name, PortNumber.

Optionally you can change your other paths such as C:\SOLR or C:\NSSM or C:\Java\JRE to whatever you need them to be.
