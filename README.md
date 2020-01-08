Sidetalk
========

Introduction
------------

Sidetalk is a new way to chat with your friends on Google Hangouts (and soon any Jabber service). Instead of a bunch of floating windows, Sidetalk tucks away neatly into the side of your screen. You can always see at a glance who's available to chat with, whether anybody is typing, and any new messages that come in. Check out the full marketing site at [sidetalk.io](http://sidetalk.io).

This app is on the Mac App Store. But I'm leaving the code visible-source here on this repo. What does this mean, exactly? I'm not exactly sure yet. At the very least, it means that all the code I've written is available for anyone to see and learn from. It means that if you have the means and know-how, you can write your own modifications to the software to better suit your needs. But of course it also means that anybody could bypass paying up via the App Store and simply build their own copy — or worse, build an unprotected copy and spread it. As long as this repository is open, there's no way for me to physically prevent that, and I'm not the legal recourse type. So if you're reading this and considering stealing it, please just be considerate.

The visible-source repository also means that people could theoretically submit pull requests. I'm not sure how to handle this yet. I haven't yet seen a paid-product open-contribution system that actually works. If you have, please send it along. In the meantime, if anybody does submit a pull request, please note that I have no idea how to compensate you monetarily -- not that I've actually made any money either.

Usage
-----

Please see the in-product getting started guide, or visit the [Sidetalk support site](https://sidetalk.freshdesk.com) for help using the application.

Known issues
------------

Most of what's wrong with the app are what it doesn't already do; that's covered below. Here's what -is- in there that doesn't work so well:

1. I don't think I'm loading everyone's names in the optimal way. I seem to pick up some but not others.
2. If you're scrolled upwards and you are messaged, the resulting notification is still offscreen at the bottom.
3. It's still possible for a notification to overlap with your current conversation if you've typed out more than one line.

What's next
-----------

Here is the list of what I'd love to tackle next. I'd love feedback on what would be most helpful to you.

1. Pinned contacts, so the most important people you always chat with are always at hand.
2. More customization: colors, placements, sizes, etc. What do you most want to customize? A lot is possible.
3. Setting your presence. Right now sidetalk doesn't even set you to available or away or anything like that.
4. Formatted messages. Bold, italics, etc. Probably not colors.

There are many more much, much larger things (stored conversation history; detachable conversation windows; multiple accounts; etc) that I'm also thinking about, but they're too numerous to list here.

Changelog
---------

1.1
* new features!
  * contact management: right-click on a contact to star or hide it. to restore a hidden contact, check the sidetalk menu.
  * short conversation history: the last few messages of each conversation are remembered and restored.
  * mute and hide settings are now saved and restored when you relaunch Sidetalk.
* fixed many bugs:
  * connection/login crashes will no longer take out the app.
  * couldn't scroll to the very top of a conversation.
  * couldn't click on links in the latest message sometimes.
  * sometimes text measurement would end up wrong and text would then end up in the wrong bubble.
  * messages with just one unicode emoji would fail.
  * in Sierra, pressing escape caused annoying alert sounds.
  * should reset scroll to the bottom of a conversation when a message comes in background.

rc-1/1.0
* added security sandboxing.

beta-1
* first-run experience / help screen.
* added about screen.
* mouse-enabled conversation closing.
* fix some textbox height jumping upon input.
* fix a very rare but lethal threadlock issue.

alpha-2.1
* some improvements to conversation appearance:
  * add outline to message bubbles.
  * colorize bubbles differently.
  * add a bit of a background to conversations.
  * add an initial title to each conversation.
* also improve search text appearance by giving it a bit of a shadow.
* fix some rare but lethal bugs:
  * sidetalk could end up trapping the mouse excessively if a notification is clicked.
  * possible crash when receiving messages (race condition).
  * mousing above the top of the contact list would crash.

alpha-2
* mouse and scrolling support on conversation scrollbacks.
* mouse and scrolling support on contact list.
* more definite selection highlight on contact list.
* unread message count on contacts.
* fix a somewhat rare autolayout conflict bug (could occur if an active conversation drifted past the top of the screen).
* backing out of a conversation is more likely to land you somewhere you want to be.

alpha-1.1
* redid text layout system so you can select text to copy/paste across multiple messages.
* this also enables you to scroll back through messages in a conversation.
* message bubbles can now be hovered over to find out when the message was sent.
* typing notifications are now sent to the other party.

alpha-1
* authentication system completely redone for google oauth.

prelease
* initial alpha release.

License
-------

Licensed under the [WTFPL](http://www.wtfpl.net/about/).
