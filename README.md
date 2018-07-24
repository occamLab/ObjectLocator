# ViewShare for Users Who Are Blind or Visually Impaired

## General Overview

ViewShare is an application that enables a person who is blind or visually impaired (B/VI) to seek assistance with locating objects from an online, sighted volunteer.  The app fits in with the recent trend of using crowdsourcing approaches for creating assistive technology for people who are B/VI (e.g., BeMyEyes, VizWiz, AIRA).

The novelty of the app lies in its combination of input from sighted volunteers with the augmented realities features of the iPhone (ARKit).  In its current form the app allows the user to post object location jobs using a voice interface.  These jobs are sent to sighted volunteers who then indicate the location of the object in images captured from the user's phone.  Once the object is located in an image, the app uses ARKit to project the 2D pixel coordinate of the object into a 3D spatial coordinate.  The distance to the the object is then read aloud to the user whenever their phone is pointing towards the position of the located object.

There is a [separate app for the volunteer side of ViewShare](https://github.com/occamLab/ViewShareCrowdWorker).

## Usage

If there is no user logged in, the app will immediately bring you to a UI to sign into the app.  If you do not have an account you can create one either using your email address is your cell phone number.

Below, is a description of each button on the main UI along with a description of their appearance and their accessibility text.
* Logout button (accessibility label "Logout"): logout of your account 
* Restart button (accessibility label "Restart"): restart the AR session (should only be used if something major has gone wrong).  The button appears as a circular arrow.  TODO: we probably should just not have this button at all and manage the session automatically.
* 3D Feedback toggle switch (accessibility Label "3D Feedback"). When this button is on, whether or not the phone is pointing at a located object and the distance to the object are determined using 3D coordinates.  If the button is off, these spatial features are computed in the plane of the floor (X-Z plane).
* Add button (accessibliity label: "Add"): The button appears as a plus.  This button starts an object finding session.  At this point, the app will enter speech recognition mode, whereby the UI will be controlled by speech input.
* Snapshot button (accessibility label: "Snapshot"): This button takes a picture and adds it to a localization job.  By default, the app will capture an image ever 2 seconds when a job has been posted, however, if the user wants to kick off their own image capture, this button can do that.

The speech interface is activated using the "Add" button.  If the user has not spoken a command in over 60 seconds, the speech interface stops (it can be restarted with the "Add" button).
* To find an object say "Find [insert-object-name]"
* To exit the speech interface say "Stop".

TODO: How does it fit into other things we’re working on? Who’s involved, and when (e.g. “active as of summer 2018”)? 

## Architecture

How does this work overall? What do all the files in this repo do: why do they exist, and where do their distinctions lie? How do each of the files, classes, and important functions interact with each other? What algorithms/etc. are we using, how do they work?

## Current Status

Where are we in development of this? Who is working on this, and where (on what general branches, etc.) is progress being made vs. what branches are inactive/we don’t even know what they are anymore? What are next steps, bugs to fix, or things to do? (<-- this last bit can be particularly good to make sure you update every time you commit, both with big picture and short term things!!)


## Setup and Dependencies

The project utilizes CocoaPods, however, we are version controlling these Pods.  The project should not require any steps to get CocoaPods working.  To build / edit the project, make sure you open "ObjectLocator.xcworkspace" rather then "OBjectLocator.xcodeproj"

We are not putting the file `GoogleService-Info.plist` under version control.  You should download that from the "object-locator" FireBase project using the typical procedures (TODO: put a link).

## Troubleshooting and Resources

when you were setting up/working on this, what errors and issues did you run into? How did you solve them? (Include solutions and workarounds here, as well as any good resources/links -- tutorials, stackoverflow, shell commands to run, you name it.)

## Known Issues

* None
