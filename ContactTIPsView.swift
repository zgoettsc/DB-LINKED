//
//  ContactTIPsView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 4/8/25.
//


import SwiftUI

struct ContactTIPsView: View {
    var body: some View {
        List {
            Section(header: Text("Contact Information")) {
                HStack {
                    Text("Phone:")
                    Spacer()
                    Link("(562) 490-9900", destination: URL(string: "tel:5624909900")!)
                }
                HStack {
                    Text("Fax:")
                    Spacer()
                    Link("(562) 270-1763", destination: URL(string: "tel:5622701763")!)
                }
                VStack(alignment: .leading) {
                    Text("Emails:")
                    Text("enrollment@foodallergyinstitute.com")
                    Text("info@foodallergyinstitute.com")
                    Text("scheduling@foodallergyinstitute.com")
                    Text("patientbilling@foodallergyinstitute.com")
                }
            }
            Section(header: Text("Links")) {
                VStack(alignment: .leading) {
                    Link("TIPs Connect", destination: URL(string: "https://tipconnect.socalfoodallergy.org/")!)
                    Text("- Report Reactions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- General Information/Resources")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Message with On-Call Team")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Request Forms/Letters/Prescriptions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading) {
                    Link("QURE4U My Care Plan", destination: URL(string: "https://www.web.my-care-plan.com/login")!)
                    Text("- View Upcoming Appointments")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Appointment Reminders")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Sign Documents")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- View Educational Materials")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading) {
                    Link("Athena Portal", destination: URL(string: "https://11920.portal.athenahealth.com/")!)
                    Text("- View Upcoming Appointments")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Discharge Instructions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Receipts of Cash Payments for HSA & FSA")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading) {
                    Link("Netsuite", destination: URL(string: "https://6340501.app.netsuite.com/app/login/secure/privatelogin.nl?c=6340501")!)
                    Text("- TIP Fee Payments")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("  - Schedule Payments and Autopay")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Contact TIPs")
    }
}