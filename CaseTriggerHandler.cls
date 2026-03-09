public with sharing class CaseTriggerHandler {
    public static void handleCaseAfterInsert(List<Case> newRecords) {
        for(case c : newRecords) {
            // Here you can add any logic you want to execute after a case is inserted
            // For example, you can call the zendeskTicketUtils.createTicket method to create a ticket in Zendesk
            zendeskTicketUtils.TicketWrapper wrapper = new zendeskTicketUtils.TicketWrapper();
            wrapper.body = c.Description;
            wrapper.subject = c.Subject;
            wrapper.priority = c.Priority.toLowerCase(); // zendesk accepts only 'low', 'normal', 'high', 'urgent'
            wrapper.name = 'name'; // Query the Contact associated with the Case to get the name
            wrapper.email = 'email'; // query the Contact associated with the Case to get the email

            zendeskTicketUtils.createTicket(wrapper);

            makeCallout(JSON.serialize(wrapper)); // Call the future method to make the callout asynchronously
        }

    }
    @future(callout=true)
    private static void makeCallout(String params) {

        //Convert string into object (class)
        zendeskTicketUtils.TicketWrapper wrapper = (zendeskTicketUtils.TicketWrapper)JSON.deserialize(params,zendeskTicketUtils.TicketWrapper.class);
        zendeskTicketUtils.createTicket(wrapper); 

    }
}