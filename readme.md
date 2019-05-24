Run the first half of the script to populate $updates.
Make sure $updates only contains the updates you wish to install
then run 

REST-LCM-BuildPlan -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

REST-LCM-Install -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

