let functions = require('firebase-functions');
let admin = require('firebase-admin');

let firebaseConfig = JSON.parse(process.env.FIREBASE_CONFIG);

admin.initializeApp()
//admin.initializeApp(firebaseConfig);

const keyFilename="./keys/object-locator-firebase-adminsdk-on2et-4496cc5626.json";
const projectId = "object-locator" //replace with your project id
const bucketName = `${projectId}.appspot.com`;

const gcs = require('@google-cloud/storage')({
	    projectId,
	    keyFilename
});

const bucket = gcs.bucket(bucketName);

// this is just an arbitrary trigger
exports.cleanupOldDataCron = functions.pubsub.topic('hourly-tick').onPublish((event) => {
    return admin.database().ref('labeling_jobs').orderByChild('creation_timestamp').endAt((new Date).getTime()-120*1000).once('value')
	.then(function(snapshot) {
	    var jobOperations = [];
	    snapshot.forEach(function(child) {
	    	var promise1 = admin.database().ref('/labeling_jobs/' + child.key + '/additional_images').once('value').then(function(childSnapshot) {
	    		var imageCleanup = [];
	   		childSnapshot.forEach(function(subChild) {
				console.log('deleting image' + subChild.key)
				imageCleanup.push(bucket.file(subChild.key + '.jpg').delete().catch(function(error) {}))
			});
			return imageCleanup;
		 });
	    	 var promise2 = admin.database().ref('/labeling_jobs/' + child.key + '/assignmentPaths').once('value').then(function(childSnapshot) {
	    		var assignmentCleanup = [];
	   		childSnapshot.forEach(function(subChild) {
				console.log(subChild.val())
				assignmentCleanup.push(admin.database().ref(subChild.val()).remove().catch(function(error) {}))
			});
			return assignmentCleanup;
		 });
		 jobOperations.push(promise1);
		 jobOperations.push(promise2);
		 jobOperations.push(bucket.file(child.key + '.jpg').delete().catch(function(error) { console.log(error) }))
		 jobOperations.push(admin.database().ref('/responses/' + child.child("requesting_user").val() + "/" + child.key).remove().catch(function(error) { }))
	    });
	    return Promise.all(jobOperations).then(() => {
	        // ensure we don't delete data that is important for cleanup before it is read
	        var finalOperations = []
	        snapshot.forEach(function(child) {
 	           finalOperations.push(admin.database().ref('/labeling_jobs/' + child.key).remove().catch(function(error) { }))
	        });
	        return Promise.all(finalOperations);
	    });
     	}).catch(function (error) {
	    console.log(error);
	});
});

exports.sendNotification = functions.database.ref('/labeling_jobs/{jobUUID}')
    .onCreate((snap, context) => {
       console.log('received ' + context.params.jobUUID);

       const payload = {
         notification: {
	   title: 'Please help someone out.',
           body: 'Please find the requested object in the image.',
	   sound : 'default',
	   labeling_job_id: context.params.jobUUID,
	 }
       };
       // need to cache / update notification keys properly in database
       var tokenRef = admin.database().ref('notification_tokens')
       // TODOs:
       //   -it would be great to add some randomness (e.g., skip half the users)
       //   -we need to skip the users that have no notification tokens (most
	//	likely these are users of the ObjectLocator
	// set keeps track of the devices we've notified already.  This
	// prevents the same app instance from getting notified multiple
	// times if the user has signed in with more than one account.
       let notifiedTokens = new Set();
       let assignmentPaths = new Array();
       return tokenRef.orderByChild("priority").limitToFirst(50).once('value')
           .then(function(snapshot) {
	       var promises = [];
	       snapshot.forEach(function(child) {
		   var subRef = tokenRef.child(child.key);
		   var addedAssignment = false;
		   promises.push(subRef.update({'priority': -((new Date).getTime())}))
	           var promise = subRef.once("value", function(snapshot2) {
		       var userPromises = [];
		       snapshot2.forEach(function(child2) {
		           if (child2.key != "priority" && child2.key != "assignments" && !notifiedTokens.has(child2.key)) {
			       // not sure if this works across the various asynchronous threads
		               notifiedTokens.add(child2.key)
			       var promise = admin.messaging().sendToDevice(child2.key, payload).then(function (response) {
				   var writePromises = [];
			           if (!addedAssignment) {
			               // TODO: write all assignments to the labeling_jobs/jobUUID as a list of references
				       writePromises.push(subRef.child("assignments").update({[context.params.jobUUID]: {"object_to_find": snap.val()["object_to_find"], "requesting_user": snap.val()["requesting_user"], "creation_timestamp": snap.val()["creation_timestamp"]}}))
				       // not sure if this works properly across multiple promises (we write it over and over... can't be resequenced)
				       writePromises.push(admin.database().ref('labeling_jobs/' + context.params.jobUUID + "/assignmentPaths").update({[child.key]: "notification_tokens/" + child.key + "/assignments/" + context.params.jobUUID}))
				       addedAssignment = true;
				   }
				   return Promise.all(writePromises);
			    	}).catch(function (error) {
				    console.log("Error sending message:", error);
			        });
			        userPromises.push(promise)
			    }
		       });
		       return Promise.all(userPromises);
	           });
		   promises.push(promise)
	       });
	       return Promise.all(promises);
           }).then(() => {
	      // workaround related to this problem: https://stackoverflow.com/questions/44790496/cloud-functions-for-firebase-error-serializing-return-value
	      return;
    	   }).catch(function (error) {
	       console.log(error);
           });
    });


exports.addPriority = functions.auth.user().onCreate((userRecord, context) => {
       return admin.database().ref('/notification_tokens/' + userRecord.uid).update({'priority': 0})
});

// TODO: probably want to remove the notification tokens when user is deleted
