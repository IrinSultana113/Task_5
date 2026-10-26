
const container = document.getElementById("movie-container");
const statusText = document.getElementById("status");

const localeInput = document.getElementById("locale");
const seedInput = document.getElementById("seed");
const likesInput = document.getElementById("likes");
const reviewsInput = document.getElementById("reviews");

const randomSeedButton = document.getElementById("random-seed");
const tableButton = document.getElementById("table-view");
const galleryButton = document.getElementById("gallery-view");

let currentView = "table";

async function loadMovies() {
  statusText.textContent = "Loading movies...";

  const params = new URLSearchParams({
    locale: localeInput.value,
    seed: seedInput.value || "589334323",
    page: "1",
    per_page: "50",
    likes_average: likesInput.value,
    reviews_average: reviewsInput.value
  });

  try {
    const response = await fetch(`/api/movies?${params}`);
    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Could not load movies");
    }

    renderMovies(data.movies);
    statusText.textContent = `Loaded ${data.movies.length} movies`;
  } catch (error) {
    container.textContent = error.message;
    statusText.textContent = "Failed to load movies";
  }
}

function renderMovies(movies) {
  container.replaceChildren();

  if (currentView === "table") {
    const table = document.createElement("table");
    table.border = "1";

    table.innerHTML = `
      <thead>
        <tr>
          <th>#</th>
          <th>Title</th>
          <th>Year</th>
          <th>Genre</th>
          <th>Actors</th>
          <th>Likes</th>
          <th>Reviews</th>
        </tr>
      </thead>
      <tbody></tbody>
    `;

    const tbody = table.querySelector("tbody");

    movies.forEach((movie) => {
      const row = document.createElement("tr");

      const values = [
        movie.sequence + 1,
        movie.title,
        movie.year,
        movie.genre,
        movie.actors.join(", "),
        movie.likes,
        movie.reviews.length
      ];

      
      values.forEach((value) => {
        const cell = document.createElement("td");
        cell.textContent = value;
        row.appendChild(cell);
      });

      row.style.cursor = "pointer";

      const detailsRow = document.createElement("tr");
      const detailsCell = document.createElement("td");

      detailsCell.colSpan = 7;
      
      detailsCell.innerHTML = `
        <div class="movie-details-layout" style="display: flex; gap: 20px; align-items: flex-start; flex-wrap: wrap;">
            <div class="trailer-container" style="flex: 0 0 480px; max-width: 100%;">
                <video
                    controls
                    preload="metadata"
                    width="480"
                    height="270"
                    style="width: 100%; height: auto; display: block;"
                    src="${movie.trailer}">
                    Your browser does not support video playback.
                </video>
                <p><strong>${movie.title}</strong></p>
            </div>

            <div class="movie-info" style="flex: 1; min-width: 250px;">
                <h3>${movie.title}</h3>
                <strong>Synopsis:</strong>
                <p>${movie.title} is a ${movie.genre} movie released in ${movie.year}.</p>

                <strong>Cast:</strong>
                <p>${movie.actors.join(", ")}</p>

                <strong>Reviews:</strong>
                <div class="movie-reviews"></div>
             </div>
        </div>
      `;

      movie.reviews.forEach((review) => {
        const reviewItem = document.createElement("p");
        reviewItem.textContent = `${review.author}: ${review.text}`;
        detailsCell.querySelector(".movie-reviews").appendChild(reviewItem);
      });

      detailsRow.appendChild(detailsCell);
      detailsRow.hidden = true;

      row.addEventListener("click", () => {
        detailsRow.hidden = !detailsRow.hidden;
      });

      tbody.appendChild(row);
      tbody.appendChild(detailsRow);

    });

    container.appendChild(table);
  } else {
    const gallery = document.createElement("div");
    gallery.className = "gallery";

    movies.forEach((movie) => {
      const card = document.createElement("article");
      card.className = "movie-card";
      card.innerHTML = `
        <h3></h3>
        <p></p>
        <p></p>
        <p></p>
      `;

      card.querySelector("h3").textContent = movie.title;
      card.children[0].textContent = movie.title;
      card.children[1].textContent = `${movie.year} · ${movie.genre}`;
      card.children[2].textContent = `Actors: ${movie.actors.join(", ")}`;
      card.children[3].textContent = `Likes: ${movie.likes} · Reviews: ${movie.reviews.length}`;

      gallery.appendChild(card);
    });

    container.appendChild(gallery);
  }
}

[localeInput, seedInput, likesInput, reviewsInput].forEach((input) => {
  input.addEventListener("change", loadMovies);
});

randomSeedButton.addEventListener("click", () => {
  const bytes = new Uint32Array(2);
  crypto.getRandomValues(bytes);

  seedInput.value = (
    BigInt(bytes[0]) * 4294967296n + BigInt(bytes[1])
  ).toString();

  loadMovies();
});

tableButton.addEventListener("click", () => {
  currentView = "table";
  loadMovies();
});

galleryButton.addEventListener("click", () => {
  currentView = "gallery";
  loadMovies();
});

loadMovies();
