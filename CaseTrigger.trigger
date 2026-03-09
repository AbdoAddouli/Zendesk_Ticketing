trigger CaseTrigger on Case (after insert) {
    CaseTriggerHandler.handleCaseAfterInsert(Trigger.new);//List of new cases inserted

}
