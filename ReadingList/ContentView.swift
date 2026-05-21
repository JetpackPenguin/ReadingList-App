import SwiftUI
import Combine
import PhotosUI


struct Book: Codable, Identifiable, Sendable {

    let id = UUID()
    let title: String
    let coverID: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case coverID = "cover_i"
    }

    var coverURL: URL? {

        guard let coverID else { return nil }

        return URL(
            string: "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        )
    }
}

struct SearchResponse: Codable, Sendable {
    let docs: [Book]
}

struct SavedBook: Identifiable, Codable, Equatable, Sendable {

    var id: UUID = UUID()

    var title: String
    var coverID: Int?
    var currentPage: String = ""
    var finished = false
    var customImageData: Data? = nil

    var coverURL: URL? {

        guard let coverID else { return nil }

        return URL(
            string: "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        )
    }
}



private func libraryFileURL() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("myLibrary.json")
}

private func saveLibrary(_ library: [SavedBook]) {
    do {
        let data = try JSONEncoder().encode(library)
        try data.write(to: libraryFileURL(), options: .atomic)
    } catch {
        print("Save error:", error)
    }
}

private func loadLibrary() -> [SavedBook] {
    do {
        let data = try Data(contentsOf: libraryFileURL())
        return try JSONDecoder().decode([SavedBook].self, from: data)
    } catch {
        return []
    }
}


class BookSearchViewModel: ObservableObject {

    @Published var searchText = ""
    @Published var searchResults: [Book] = []
    @Published var isLoading = false
    @Published var currentPage = 1

    func searchBooks() {

        currentPage = 1
        fetchBooks()
    }

    func nextPage() {

        currentPage += 1
        fetchBooks()
    }

    func previousPage() {

        guard currentPage > 1 else { return }

        currentPage -= 1
        fetchBooks()
    }

    private func fetchBooks() {

        guard !searchText.isEmpty else { return }

        isLoading = true

        let encodedQuery =
            searchText.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? ""

        let urlString =
            "https://openlibrary.org/search.json?q=\(encodedQuery)&page=\(currentPage)"

        guard let url = URL(string: urlString) else {

            isLoading = false
            return
        }

        Task {

            do {

                let (data, _) =
                    try await URLSession.shared.data(from: url)

                let decoded =
                    try JSONDecoder().decode(
                        SearchResponse.self,
                        from: data
                    )

                await MainActor.run {

                    self.searchResults =
                        Array(decoded.docs.prefix(10))

                    self.isLoading = false
                }

            } catch {

                await MainActor.run {
                    self.isLoading = false
                }

                print(error)
            }
        }
    }
}



struct ContentView: View {

    @StateObject private var viewModel = BookSearchViewModel()

    @State private var myLibrary: [SavedBook] = loadLibrary()
    @State private var showAddedAlert = false
    @State private var addedBookTitle = ""
    @State private var editMode: EditMode = .inactive
    @State private var showAddCustomBook = false
    @State private var customTitle = ""
    @State private var customImageItem: PhotosPickerItem? = nil
    @State private var customImageData: Data? = nil

    var body: some View {

        TabView {

            SearchTabView(
                viewModel: viewModel,
                myLibrary: $myLibrary,
                showAddedAlert: $showAddedAlert,
                addedBookTitle: $addedBookTitle
            )
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            LibraryTabView(
                myLibrary: $myLibrary,
                editMode: $editMode,
                showAddCustomBook: $showAddCustomBook,
                customTitle: $customTitle,
                customImageItem: $customImageItem,
                customImageData: $customImageData
            )
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }
        }
        .onChange(of: myLibrary) { newValue in
            saveLibrary(newValue)
        }
    }
}


struct SearchTabView: View {

    @ObservedObject var viewModel: BookSearchViewModel
    @Binding var myLibrary: [SavedBook]
    @Binding var showAddedAlert: Bool
    @Binding var addedBookTitle: String

    var body: some View {

        NavigationView {

            VStack {

                HStack {

                    TextField("Search books...", text: $viewModel.searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Search") {
                        viewModel.searchBooks()
                    }
                }
                .padding()

                List {
                    ForEach(viewModel.searchResults) { book in
                        Button {
                            myLibrary.append(
                                SavedBook(title: book.title, coverID: book.coverID)
                            )
                            addedBookTitle = book.title
                            showAddedAlert = true
                        } label: {
                            HStack(spacing: 12) {
                                BookCoverView(coverURL: book.coverURL)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .multilineTextAlignment(.leading)
                                    Text("Tap to add")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 20) {

                    Button {
                        viewModel.previousPage()
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(viewModel.currentPage == 1)

                    Text("Page \(viewModel.currentPage)")
                        .font(.headline)

                    Button {
                        viewModel.nextPage()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                }
                .padding()

                if viewModel.isLoading {
                    ProgressView().padding(.bottom)
                }
            }
            .navigationTitle("Search Books")
            .alert("Added to Library", isPresented: $showAddedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\"\(addedBookTitle)\" was added.")
            }
        }
    }
}


struct LibraryTabView: View {

    @Binding var myLibrary: [SavedBook]
    @Binding var editMode: EditMode
    @Binding var showAddCustomBook: Bool
    @Binding var customTitle: String
    @Binding var customImageItem: PhotosPickerItem?
    @Binding var customImageData: Data?

    var finishedCount: Int { myLibrary.filter { $0.finished }.count }
    var ongoingCount: Int  { myLibrary.filter { !$0.finished }.count }

    var body: some View {

        NavigationView {

            VStack(spacing: 0) {

                HStack(spacing: 20) {

                    VStack {
                        Text("\(finishedCount)").font(.largeTitle).bold()
                        Text("Finished").font(.caption).foregroundColor(.secondary)
                    }

                    VStack {
                        Text("\(ongoingCount)").font(.largeTitle).bold()
                        Text("Ongoing").font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding()

                List {
                    if myLibrary.isEmpty {
                        ContentUnavailableView(
                            "No Books Yet",
                            systemImage: "books.vertical",
                            description: Text("Search and save books to your library.")
                        )
                    } else {
                        ForEach($myLibrary) { $book in
                            LibraryRowView(book: $book)
                        }
                        .onDelete { offsets in
                            withAnimation { myLibrary.remove(atOffsets: offsets) }
                        }
                    }
                }
            }
            .navigationTitle("My Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if editMode == .active {
                        Button {
                            customTitle = ""
                            customImageItem = nil
                            customImageData = nil
                            showAddCustomBook = true
                        } label: {
                            Label("Add Custom Book", systemImage: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showAddCustomBook) {
                AddCustomBookSheet(
                    myLibrary: $myLibrary,
                    isPresented: $showAddCustomBook,
                    customTitle: $customTitle,
                    customImageItem: $customImageItem,
                    customImageData: $customImageData
                )
            }
        }
    }
}


struct LibraryRowView: View {

    @Binding var book: SavedBook

    var body: some View {

        HStack(alignment: .top, spacing: 12) {

            BookCoverView(
                coverURL: book.coverURL,
                imageData: book.customImageData
            )

            VStack(alignment: .leading, spacing: 10) {

                Text(book.title).font(.headline)

                TextField("Current page", text: $book.currentPage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Toggle("Finished", isOn: $book.finished)
            }
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Add Custom Book Sheet

struct AddCustomBookSheet: View {

    @Binding var myLibrary: [SavedBook]
    @Binding var isPresented: Bool
    @Binding var customTitle: String
    @Binding var customImageItem: PhotosPickerItem?
    @Binding var customImageData: Data?

    var body: some View {

        NavigationView {

            Form {

                Section("Book Title") {
                    TextField("Enter title...", text: $customTitle)
                }

                Section("Cover Image") {

                    PhotosPicker(
                        selection: $customImageItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            if let data = customImageData,
                               let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 44, height: 66)
                                    .overlay {
                                        Image(systemName: "photo.badge.plus")
                                            .foregroundColor(.gray)
                                    }
                            }
                            Text(customImageData == nil ? "Choose Photo" : "Change Photo")
                                .foregroundColor(.accentColor)
                                .padding(.leading, 8)
                        }
                    }
                    .onChange(of: customImageItem) { newItem in
                        Task {
                            if let data = try? await newItem?
                                .loadTransferable(type: Data.self) {
                                customImageData = data
                            }
                        }
                    }
                }
            }
            .navigationTitle("Custom Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = customTitle.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        withAnimation {
                            myLibrary.append(
                                SavedBook(title: trimmed, customImageData: customImageData)
                            )
                        }
                        isPresented = false
                    }
                    .disabled(customTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}


struct BookCoverView: View {

    let coverURL: URL?
    var imageData: Data? = nil

    var body: some View {

        if let data = imageData, let uiImage = UIImage(data: data) {

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))

        } else if let url = coverURL {

            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        } else {

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 60)
                .overlay {
                    Image(systemName: "book").foregroundColor(.gray)
                }
        }
    }
}


#Preview {
    ContentView()
}
