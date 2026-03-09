public with sharing class zendeskTicketUtils {

    // test code to create a ticket in zendesk using the wrapper class and the createTicket method
    /*
    zendeskTicketUtils.TicketWrapper wrapper = new zendeskTicketUtils.TicketWrapper();
wrapper.subject = 'Test Ticket';
wrapper.body = 'This is a test ticket created from Salesforce.';
wrapper.priority = 'normal';
wrapper.name = 'John Doe';
wrapper.email = 'john.doe@example.com';

zendeskTicketUtils.createTicket(wrapper);
     */

    // Wrapper class to hold the ticket data and make it Dynamic
    public class TicketWrapper{
        public String subject;
        public String body;
        public String priority;
        public String name;
        public String email;
    }
    public static void createTicket( TicketWrapper wrapper) {
        String header = System.label.Zendesk_Username + ':' + System.label.Zendesk_Api_Token; // Assuming you have a custom label for the header/token
        httpRequest req = new httpRequest();
        String requestBody = '{"ticket": {"subject": "' + wrapper.subject + '", "comment": {"body": "' + wrapper.body + '"}, "priority": "' + wrapper.priority + '", "requester": {"name": "' + wrapper.name + '", "email": "' + wrapper.email + '"}}}';
        System.debug('Request Body: ' + requestBody); // Debug the request body to ensure it's correctly formatted
        
        req.setEndpoint('https://yourdomain.zendesk.com/api/v2/tickets.json'); // Replace with your Zendesk API endpoint
        req.setMethod('POST');
        req.setBody(requestBody);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(header))); // check EncodingUtil class for more info
        

        Http http = new Http();

        try {

            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 201) {
                // Ticket created successfully
                System.debug('Ticket created successfully: ' + res.getBody());
            }else {
                // there is an error should be handled here
                System.debug('Failed to create ticket. Status code: ' + res.getStatusCode() + ', Response: ' + res.getBody());
            }
            
        } catch (System.CalloutException ex) {
            System.debug('Callout error: ' + ex);
            
        } catch (Exception e) {
            System.debug('Error: ' + e);
        }
    }
}